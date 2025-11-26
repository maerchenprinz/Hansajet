#############################################################################
# a two pole, internally represented as a current source i0 with a
# parallel conductance g0
#############################################################################
var TwoPole = {
  new : func(base) {
    var obj = { parents : [TwoPole] };
    obj.base = globals.isa( base, props.Node ) ? base : props.globals.getNode( base );

    obj.i0Node = obj.base.initNode( "i0-amps", 0.0 );
    obj.g0Node = obj.base.initNode( "g0-siemens", 0.0 );
    obj.iNode  = obj.base.initNode( "current-a", 0.0 );
    obj.uNode = obj.base.initNode( "voltage-v", 0.0 );
    obj.conditionNode = obj.base.getNode("condition");

    return obj;
  },

  set_g0 : func(gi) { me.g0Node.setDoubleValue(gi); },
  get_g0 : func     { return props.condition(me.conditionNode) ? me.g0Node.getValue() : 0; },
  set_i0 : func(i0) { me.i0Node.setDoubleValue(i0); },
  get_i0 : func     { return props.condition(me.conditionNode) ? me.i0Node.getValue() : 0; },
  set_i  : func(i)  { me.iNode.setDoubleValue(i); },
  get_i  : func     { return props.condition(me.conditionNode) ? me.iNode.getValue() : 0; },

  set_u  : func(u)  { 
    me.uNode.setDoubleValue(u); 
    me.i0Node.setDoubleValue( u * me.g0Node.getValue() );
  },

  get_u  : func     { return props.condition(me.conditionNode) ? me.uNode.getValue() : 0; },
  update : func     {}
};

#############################################################################
# a simple generator, derivate of a two pole
#############################################################################
var Generator = {
  new : func(base) {
    var obj = { parents : [Generator, TwoPole.new(base)] };

    var n = obj.base.getNode( "source", 1 );
    obj.sourceN = props.globals.getNode( n.getValue(), 1 );
    obj.scaleN  = obj.base.initNode( "scale", 1.0 );
    obj.offsetN = obj.base.initNode( "offset", 0.0 );
    obj.minVN   = obj.base.getNode( "min-v" );
    obj.maxVN   = obj.base.getNode( "max-v" );
    obj.maxAN   = obj.base.getNode( "max-a" );
    obj.lowpass = aircraft.lowpass.new(1);

    obj.set_g0(6.25); # 160 Ohm
    return obj;
  },

  update : func(dt ) {
    var u = 0;
    if( props.condition(me.conditionNode) ) {
      u = me.sourceN.getValue() * me.scaleN.getValue() + me.offsetN.getValue();
      if( me.minVN != nil and u < me.minVN.getValue() ) u = me.minVN.getValue();
      if( me.maxVN != nil and u > me.maxVN.getValue() ) u = me.maxVN.getValue();
    }
    me.set_u( me.lowpass.filter(u) );
  }
};

#############################################################################
# a battery
# 
# http://www.dtic.mil/cgi-bin/GetTRDoc?AD=AD405904&Location=U2&doc=GetTRDoc.pdf
# discharge curve
# E = 1.25 - 0.025 * (1/(1-1.05*it))*i - 0.006*i + 0.095*exp(-3.83*it)
#
# charge curve
# E = 1.379 + 0.0024*(1/(1-0.095it))*i - 0.00117*i - 0.08*exp(-0.693*it)
#############################################################################
var Battery = {
  new : func(base) {
    var obj = { parents : [Battery, TwoPole.new(base)] };

    obj.designVoltage = obj.base.initNode("design-voltage-v", 12 );
    obj.designCapacity = obj.base.initNode("design-capacity-ah", 25 );
    obj.capacity = obj.base.initNode( "capacity-ah", obj.designCapacity.getValue() );
    obj.capacityNorm = obj.base.getNode( "capacity-norm", 1 );
    obj.lowpass = aircraft.lowpass.new(100);
    return obj;
  },

  update : func(dt) {
    # the current into(+) our out (-) of the battery
    var i = me.get_i();

    # "normalized" by the capacity
    var in = math.abs(i / me.designCapacity.getValue());

    # charge/discharge, integrate current over time
    var c = me.capacity.getValue() + i*dt/3600;
    me.capacity.setDoubleValue( c );

    # normalize capacity
    var cn = c / me.designCapacity.getValue();
    me.capacityNorm.setDoubleValue( cn );

    # calculate voltage for a NiCd battery due to current and capacity
    var u = 0;
    if( i > 0 ) {
      # charge
      u = 1.379 + 0.0024*(1/(1-0.095*cn))*in - 0.00117*in - 0.08*math.exp(-0.693*cn)
    } else {
      # discharge
      u = 1.25 - 0.025 * (1/(1-1.05*(1-cn)))*in - 0.006*in + 0.095*math.exp(-3.83*(1-cn))
    }

    # minimum clamp
    if( u < 0.2 ) u = 0.2;
    me.set_u( me.lowpass.filter(u * 20) );
  },
};

#############################################################################
# a Bus has zero to unlimited elements connected. All elements are converted
# to a current source with a parallel conductance (reciprocal resistance).
#############################################################################
var Bus = {
  new : func( base ) {
    var obj = { parents : [ Bus,TwoPole.new(base) ] };
    obj.name = obj.base.getNode("name",1).getValue();
    obj.gtot = 0;
    obj.itot = 0;
    obj.tied = 0;

    obj.elements = [];
    
    var knownElements = {
      load : TwoPole.new,
      battery : Battery.new,
      generator : Generator.new,
    };

    foreach( var child; obj.base.getChildren() ) {
      var f = knownElements[child.getName()];
      f != nil and append( obj.elements, f( child ) );
    }

    print( "Electrical bus created: ", obj.name );
    return obj;
  },

  createSubstitudeCurrentSource : func(dt) {
    # sum all currents and conductances to create
    # a substitude current source
    me.gtot = 0.0;
    me.itot = 0.0;

    foreach( var element; me.elements ) {
      element.update(dt);

      me.gtot += element.get_g0();
      me.itot += element.get_i0();
    }

    me.set_g0(me.gtot);
    me.set_i0(me.itot);
  },

  computeVoltage : func {
    # U = I * R = I / G
    me.u = me.gtot <= 0.0 ? 0.0 : me.itot / me.gtot;
    me.uNode.setDoubleValue( me.u );
  },

  computeChilds : func(dt) {

    # now compute the currents for each element
    foreach( var element; me.elements ) {
      var i = me.u * element.get_g0() - element.get_i0();
      element.set_i(i);
    }
  }

};

var BusTie = {
  new : func(base) { 
    var obj = { parents : [ BusTie, TwoPole.new(base) ] };
    obj.conditionNode = obj.base.getNode("condition");
    obj.busids = obj.base.getChildren("bus-id");
    obj.gtot = 0.0;
    obj.itot = 0.0;
    obj.x = nil;
    obj.busses = nil;
    return obj;
  },

  compute : func(busses) {
    # check tied condition
    props.condition(me.conditionNode) == 0 and return;

    # sum up all tied busses: i0 and g0
    me.gtot = 0.0;
    me.itot = 0.0;

    # lazily create vector of connected buses on
    # first call
    if( me.busses == nil ) {
      me.busses = [];
      foreach( var busidN; me.busids ) {
        var busid = busidN.getValue();
        var bus = busses[busid];
        if( bus == nil ) continue;
        append( me.busses, bus );
      }
    }

    foreach( var bus; me.busses ) {
      # set tied flag
      bus.tied = 1;
      me.gtot += bus.get_g0();
      me.itot += bus.get_i0();
    }

    me.set_g0(me.gtot);
    me.set_i0(me.itot);

    # calculate tied buses voltage
    me.u = me.gtot <= 0.0 ? 0.0 : me.itot / me.gtot;
    me.uNode.setDoubleValue( me.u );

    # same voltage for all tied busses
    foreach( var bus; me.busses ) {
      bus.u = me.u;
      bus.uNode.setDoubleValue( bus.u );
    }
  }
};

#############################################################################
# the electrical system
#############################################################################
var ElectricSystem = {
  new : func(base) {
    print( "Electrical System: initializing" );
    var obj = { 
      parents : [ElectricSystem],
      bus : [],
      bustie : [],
      baseNode : globals.isa(base,props.Node) ? base : props.globals.getNode(base,1),
      elapsedTimeNode : props.globals.getNode( "/sim/time/elapsed-sec", 1 ),
      t_last : 0,
    };

    foreach( var busNode; obj.baseNode.getChildren( "bus" ) )
      append( obj.bus, Bus.new( busNode ) );

    foreach( var bustieNode; obj.baseNode.getChildren( "bus-tie" ) )
      append( obj.bustie, BusTie.new( bustieNode ) );

    print( "Electrical System: initialized" );
    return obj;
  },

  update : func {
    var t_now = me.elapsedTimeNode.getValue();
    var dt = t_now - me.t_last;
    me.t_last = t_now;
  
    # create a substitude current source for each bus
    foreach( var bus; me.bus ) {
      # reset tied flag
      bus.tied = 0;
      bus.createSubstitudeCurrentSource(dt);
    }

    # create a substitude current source for each tied bus
    foreach( var bustie; me.bustie )
      bustie.compute(me.bus);

    # compute the bus-voltage and childs if this bus is
    # not tied. If it is tied, BusTie already did it
    foreach( var bus; me.bus ) {
      if( bus.tied == 0 )
        bus.computeVoltage();

      # and compute the currents of each element
      bus.computeChilds(dt);
    }

    # compute the voltage for each untied bus and for the tied busses
    #}

    settimer( func { me.update() }, 0.1 );
  }
};

##############################################################################
#

var electricSystem = nil;

var l = setlistener("/sim/signals/fdm-initialized", func {
  
  electricSystem = ElectricSystem.new("/systems/electrical");
  electricSystem.update();
  removelistener(l);
});

