controls.startEngine = func(v = 1) {
    if (!v)
        return props.setAll("/controls/engines/engine", "starter-switch", 0);
    foreach(var e; controls.engines)
        if(e.selected.getValue()) {
            var n = e.controls.getNode("starter-switch");
            n != nil and n.setBoolValue(v);
        }
}

##################### Master Caution ##########################
var MasterCaution = {
  new : func {
    var obj = { parents : [MasterCaution] };
    obj.reset1N = props.globals.initNode("/instrumentation/warning-panel/master-caution-reset[0]", 0, "BOOL" );
    obj.reset2N = props.globals.initNode("/instrumentation/warning-panel/master-caution-reset[1]", 0, "BOOL" );
    obj.outN = props.globals.initNode("/instrumentation/warning-panel/master-caution", 0, "BOOL" );
    obj.inNodes = [];

    setlistener( obj.reset1N, func(n) { obj.reset(n); }, 0, 0 );
    setlistener( obj.reset2N, func(n) { obj.reset(n); }, 0, 0 );
    return obj;
  },

  addListener : func( nodeName ) {
    append( inNodes, nodeName );
    setlistener( nodeName, func(n) { me.listener(n); }, 1, 0 );
  },

  listener : func(n) {
    if( n.getValue() > 0 )
      me.outN.setBoolValue( 1 );
  },

  reset : func(n) {
    if( n.getValue() > 0 )
      me.outN.setBoolValue( 0 );
  }
};

##################### Windshield Wiper ########################
var Wiper = {
  new : func( index ) {
    var obj = { parents : [Wiper] };
    obj.base = props.globals.getNode("/systems/wiper[" ~ index ~ "]", 1 );
    obj.timer = aircraft.door.new( obj.base.getPath(), 1 );
    obj.switch = props.globals.initNode("/controls/windshield/wiper[" ~ index ~ "]", 0, "BOOL" );
    return obj;
  },

  update : func {
    if( me.timer.getpos() == 1 ) {
      me.timer.close();
      return;
    }

    if( me.timer.getpos() == 0 and me.switch.getValue() == 1 ) {
      me.timer.open();
      return;
    }
  },
};

##################### Hydraulic System ########################
var HydraulicLoad = {};
HydraulicLoad.new = func( power ) {
  var obj = {};
  obj.parents = [HydraulicLoad];
  obj.power = power;
  return obj;
};

HydraulicLoad.getPressure = func( dt, pressure ) {
  return pressure - me.power * dt;
};

var HydraulicPump = {};
HydraulicPump.new = func( source, offset, factor, power ) {
  var obj = {};
  obj.parents = [HydraulicPump];

  obj.sourceNode = props.globals.initNode( source, 0.0 );
  obj.offset = offset;
  obj.factor = factor;
  obj.power = power;
  return obj;
};

HydraulicPump.getPressure = func( dt, pressure ) {
  var power = me.power * ( (me.sourceNode.getValue() - me.offset ) * me.factor );

  if( power < 0 )
    power = 0;

  if( power > me.power )
    power = me.power;

  return pressure + power * dt;
};

###
var HydraulicReservoir = {};
HydraulicReservoir.new = func( rootNode, index ) {
  var obj = {};
  obj.parents = [HydraulicReservoir];

  obj.rootNode = props.globals.getNode( rootNode ~ "[" ~ index ~ "]", 1 );
  obj.temperatureDegCNode = obj.rootNode.initNode( "temp-degc", getprop( "environment/temperature-degc" ), "DOUBLE" );
  obj.capacityNode = obj.rootNode.initNode( "capacity-l", 20.0 );
  obj.levelNormNode = obj.rootNode.initNode( "level-norm", 0.9 );
  obj.minLevelNormNode = obj.rootNode.initNode( "min-level-norm", 0.1 );

  return obj;
}

HydraulicReservoir.isEmpty = func {
  return me.levelNormNode.getValue() < me.minLevelNormNode.getValue();
}
###

var HydraulicSystem = {};
HydraulicSystem.new = func( rootNode, index ) {
  var obj = {};
  obj.parents = [HydraulicSystem];
  obj.rootNode = props.globals.getNode( rootNode ~ "[" ~ index ~ "]", 1 );

  obj.pressureNode = obj.rootNode.initNode( "pressure-psi", 0.0 );
# AFM 4.21
  obj.maxPressureNode = obj.rootNode.initNode( "max-pressure-psi", 3000.0 );

  obj.pumps = [];
  obj.reservoirs = [];
  obj.loads = [];
  print( "Hydraulic System " ~ index ~ " ready" );
  return obj;
};

HydraulicSystem.addPump = func( hydraulicPump ) {
  append( me.pumps, hydraulicPump );
};

HydraulicSystem.addLoad = func( hydraulicLoad ) {
  append( me.loads, hydraulicLoad );
};
HydraulicSystem.addReservoir = func( hydraulicReservoir ) {
  append( me.reservoirs, hydraulicReservoir );
}

HydraulicSystem.hasFluid = func {
  foreach( var reservoir; me.reservoirs ) {
    if( reservoir.isEmpty() == 0) {
      return 1;
    }
  }
  return 0;
}

HydraulicSystem.update = func( dt ) {
  var pressure = me.pressureNode.getValue();
  var maxPressure = me.maxPressureNode.getValue();

  # use the pumps to increase the pressure
  # if we have at least one not empty reservoir
  if( me.hasFluid() ) {
    foreach( var pump; me.pumps ) {
      pressure = pump.getPressure( dt, pressure );
    }
  }

  if( pressure > maxPressure )
    pressure = maxPressure;

  # use the load to decrease the pressure
  foreach( var load; me.loads ) {
    pressure = load.getPressure( dt, pressure );
  }

  if( pressure < 0 )
    pressure = 0;

  me.pressureNode.setDoubleValue( pressure );
};



############################################################################
# Engine control
# Startup procedure JSBSim
# cutoff=true
# start=true
# wait for n2 > idlen2
# ...
# Startup procedure Hansa Jet
# Stop=off
# FuelPump(WingTankMain/Aux)=on
# Start=on
# Throttle=Idle at %xRPM
############################################################################

var Engine = {};
Engine.new = func(index, cutoffNode) {
  var obj = {};
  obj.parents = [Engine];
  obj.enginesOffNode = cutoffNode;

  obj.controlsRootNode = props.globals.getNode( "controls/engines/engine[" ~ index ~ "]", 1 );
  obj.engineRootNode = props.globals.getNode( "engines/engine[" ~ index ~ "]", 1 );
  obj.n2Node = obj.engineRootNode.getNode( "n2", 1 );
  obj.ignitionNode = obj.engineRootNode.initNode( "ignition", 0, "BOOL" );
  obj.starterOnTime = 0;
  obj.crankingNode = obj.engineRootNode.initNode( "cranking2", 0, "BOOL" );

  obj.cutoffNode = obj.controlsRootNode.getNode( "cutoff", 1 );
  obj.starterSwitchNode = obj.controlsRootNode.initNode( "starter-switch", 0, "BOOL" );
  obj.starterNode = obj.controlsRootNode.initNode( "starter", 0, "BOOL" );
  obj.throttleNode = obj.controlsRootNode.getNode( "throttle", 1 );
  obj.throttleTakeOffNode = obj.controlsRootNode.initNode( "throttle-take-off", 0, "BOOL" );
  obj.throttleLowNode = obj.controlsRootNode.initNode( "throttle-low", 0, "BOOL" );
  setlistener( obj.throttleNode, func(n) { obj.throttleListener(n); }, 1, 0 );
  obj.runningNode = obj.engineRootNode.getNode( "running", 1 );

  obj.ignitionSwitchNode = obj.controlsRootNode.initNode( "ignition", 0, "BOOL" );
  obj.ignitionSwitchOnTime = 0;
  obj.ignitionSwitchLast = obj.ignitionSwitchNode.getValue();

  obj.ignitionLightNode = obj.controlsRootNode.getNode( "ignition-light", 1 );

  obj.fuelPressureNode = obj.engineRootNode.initNode("fuel-pressure-psi", 0.0 );

  print( "Engine handler #" ~ index ~ " created" );
  return obj;
};

Engine.throttleListener = func(n) {
  var throttlePos = n.getValue();
  me.throttleTakeOffNode.setBoolValue( throttlePos > 0.98 );
  me.throttleLowNode.setBoolValue( throttlePos < 0.50 );
};

#ignition auto off at 37% N1

# operations manual page 12-12
Engine.update = func( dt ) {
  var throttle = me.throttleNode.getValue();

  #immediate stop: cut off
  if( me.enginesOffNode.getValue() ) {
    me.cutoffNode.setBoolValue( 1 );
    me.ignitionNode.setBoolValue( 0 );
    me.crankingNode.setBoolValue( 0 );
    me.starterNode.setBoolValue( 0 );
    return;
  }

  if( me.starterSwitchNode.getValue() ) {
    me.starterOnTime += dt;
    me.starterNode.setBoolValue( 1 );
#    me.crankingNode.getValue() == 0 and me.crankingNode.setBoolValue( 1 );
  } else {
    if( me.starterOnTime > 0 ) {
      if( me.starterOnTime < 2.5 ) {
        print( "starter time to short, start at least for 2.5 seconds");
        me.starterNode.setBoolValue( 0 );
        me.cutoffNode.setBoolValue( 1 );
        me.crankingNode.setBoolValue( 0 );
        me.starterOnTime = 0;
      }
    }
    me.starterOnTime = 0;
  }

  var ignition = 0;
  # ignition and starter cut off at 37% RPM
  if( me.n2Node.getValue() > 37 ) {
    if( me.crankingNode.getValue() ) {
      me.crankingNode.setBoolValue( 0 );
      ignition = 0;
    }
  } else {
    if ( throttle > 0.1 ) ignition = 1;
  }

  # ignition by ignition switch limited to 45 seconds
  var v = me.ignitionSwitchNode.getValue();
  if( v ) {
    if( v != me.ignitionSwitchLast ) {
      me.ignitionSwitchOnTime = timeNode.getValue();
    }
    ignition = (timeNode.getValue() - me.ignitionSwitchOnTime) < 45;
  } 
  me.ignitionSwitchLast = v;

  me.ignitionNode.getValue() != ignition and me.ignitionNode.setBoolValue( ignition );

  var cutoff = 0;
  if( cutoff == 0 ) cutoff = (throttle < 0.05);
#  if( cutoff == 0 ) cutoff = (me.fuelPressureNode.getValue() < 8.0);
  me.cutoffNode.setBoolValue( cutoff );

};

var Engines = {};
Engines.new = func(count) {
  var obj = {};
  obj.parents = [Engines];
  obj.cutoffNode = props.globals.getNode( "controls/engines/off", 1 );

  obj.engines = [];
  for( var i = 0; i < count; i = i + 1 ) {
    append( obj.engines, Engine.new( i, obj.cutoffNode ) );
  }

  return obj;
};

Engines.update = func( dt ) {
  foreach( var engine; me.engines ) {
    engine.update( dt );
  }
};

####################################################################
var FuelPump = {};

FuelPump.new = func(base) {
  var obj = {};
  obj.parents = [FuelPump];
  obj.baseNode = base;

  var n = base.getNode( "enable-prop" );
  if( n != nil ) {
    obj.enableNode = props.globals.initNode( n.getValue(), 0, "BOOL" );
  } else {
    obj.enableNode = base.initNode( "enabled", 0, "BOOL" );
  }

  n = base.getNode( "source-tank", 1 );
  obj.sourceNode = props.globals.initNode( "/consumables/fuel/tank[" ~ n.getValue() ~ "]/level-gal_us", 0.0 );
  obj.destinationNodes = [];
  foreach( n; base.getChildren("destination-tank") ) {
    append( obj.destinationNodes,
      props.globals.initNode( "/consumables/fuel/tank[" ~ n.getValue() ~ "]/level-gal_us", 0.0 ) );
  }

  obj.max_fuel_flow_gps = base.initNode( "max-fuel-flow-pph", 0.0 ).getValue() / 3600 / 6.6;
  obj.serviceableNode = base.initNode( "serviceable", 1, "BOOL" );

  v = base.getNode( "name" );
  if( v != nil )
    v = v.getValue();
  else
    v = "unnamed";
  print( "FUEL PUMP ", v, " initialized" );
  return obj;
};

FuelPump.update = func(dt) {
  #if its of, go away
  !me.enableNode.getValue() and return;
  #if its broken, go away
  !me.serviceableNode.getValue() and return;

  # compute fuel flow
  var transfer_fuel = me.max_fuel_flow_gps * dt;
  #consume fuel, up to the available level
  var source_level = me.sourceNode.getValue();
  if( transfer_fuel > source_level )
    transfer_fuel = source_level;
  source_level -= transfer_fuel;
  me.sourceNode.setDoubleValue( source_level );

  #devide fuel by number of destinations
  transfer_fuel /= size(me.destinationNodes);  

  foreach( var n; me.destinationNodes ) {
    n.setDoubleValue( n.getValue() + transfer_fuel );
  }
}

FuelPump.hasFuel = func {
  return me.sourceNode.getValue() > 0.01;
};

####################################################################

var FuelTransferUnit = {};

FuelTransferUnit.new = func(base) {
  var obj = {};
  obj.parents = [FuelTransferUnit];
  obj.pumpEnableNode = props.globals.initNode( base.getNode("pump",1).getValue() ~ "/enabled",0,"BOOL");
  obj.on = base.getNode("on-level-kg", 1 ).getValue() * 2.2;
  obj.off = base.getNode("off-level-kg", 1 ).getValue() * 2.2;
  return obj;
};

FuelTransferUnit.update = func(dt, level ) {
  level < me.on  and me.pumpEnableNode.setBoolValue( 1 );
  level > me.off and me.pumpEnableNode.setBoolValue( 0 );
}

####################################################################

#TODO: Tip Tank Emergency Transfer (gravity feed)
#TODO: Fuel Pump Unserviceable if tank empty
var AutoSequencer = {};

AutoSequencer.new = func(base) {
  var obj = {};
  obj.parents = [AutoSequencer];
  obj.baseNode = base;
  var n = base.getNode("tank-number", 1 );
  obj.tankLevelNode = props.globals.initNode( "consumables/fuel/tank[" ~ n.getValue() ~ "]/level-gal_us", 0.0 );
  obj.enabledNode = base.initNode( "enabled", 0, "BOOL" );
  obj.serviceableNode = base.initNode( "serviceable", 1, "BOOL" );

  obj.transferUnits = [];
  foreach( n; base.getChildren( "transfer-unit" ) )
    append( obj.transferUnits, FuelTransferUnit.new( n ) );

  print( "AUTO SEQUENCER: ready" );
  return obj;
};

AutoSequencer.update = func(dt) {
  !me.enabledNode.getValue() and return;
  !me.serviceableNode.getValue() and return;

  foreach( var n; me.transferUnits ) {
    n.update(dt, me.tankLevelNode.getValue() * 6.6 );
  }
};

####################################################################

var FuelTank = {};

FuelTank.new = func(index) {
  var obj = {};
  obj.parents = [FuelTank];
  obj.rootNode = props.globals.getNode( "consumables/fuel/tank[" ~ index ~ "]", 1 );
  obj.levelNode = obj.rootNode.initNode( "level-lbs", 0.0 );
  obj.lastLevel = obj.levelNode.getValue();

  obj.index = index;
  return obj;
};

FuelTank.getFuelUsed = func {
  var level = me.levelNode.getValue();
  if( level == nil )
    level = 0.0;

  var fuelUsed = me.lastLevel - level;
  me.lastLevel = level;

  # refuelling - don't count
  if( fuelUsed < 0 )
    fuelUsed = 0;

  return fuelUsed/2.2;
};

var FuelTanks = {};
FuelTanks.new = func(count) {
  var obj = {};
  obj.parents = [FuelTanks];
  obj.usedNode = props.globals.getNode( "consumables/fuel/used-kg", 1 );
  obj.fuelTanks = [];
  for( var i = 0; i < count; i = i + 1 ) {
    append( obj.fuelTanks, FuelTank.new(i) );
  }

  return obj;
};

FuelTanks.update = func( dt ) {
  var fuelUsed = me.usedNode.getValue();
  if( fuelUsed == nil )
    fuelUsed = 0.0;

  foreach( var fuelTank; me.fuelTanks ) {
    fuelUsed = fuelUsed + fuelTank.getFuelUsed();
  }

  me.usedNode.setDoubleValue( fuelUsed );
}

####################################################################

var WindshieldHeater = {};

WindshieldHeater.new = func( idx ) {
  var obj = {};
  obj.parents = [WindshieldHeater];
  obj.onNode = props.globals.initNode( "controls/anti-ice/window-heat[" ~ idx ~ "]", 0, "BOOL" );
  obj.testNode = props.globals.initNode( "controls/anti-ice/test-overheat", 0, "BOOL" );
  obj.maxTempNode = props.globals.getNode( "systems/anti-ice/max-window-temperature-degc", 80.0 );
  obj.oatNode = props.globals.initNode( "environment/temperature-degc", 0.0 );
  obj.machNode = props.globals.getNode( "velocities/mach", 1 );

  obj.temperatureNode = props.globals.getNode( "systems/anti-ice/window-temperature-degc[" ~ idx ~ "]", 1 );
  obj.temperatureNode.setDoubleValue( obj.oatNode.getValue() );
  obj.overHeatNode = props.globals.getNode( "systems/anti-ice/window-heat-overheat[" ~ idx ~ "]", 1 );

  return obj;
}

WindshieldHeater.update = func( dt ) {
  var temp = me.temperatureNode.getValue();
  var deltaTemp = me.oatNode.getValue() - temp;
  var mach = me.machNode.getValue();
  var tempRate = (0.01 + mach * mach * 0.99) * dt;

  temp = temp + deltaTemp * tempRate;

  var overheat = 0;
  if( me.onNode.getValue() ) {
    temp = temp + 5 * dt;
    overheat = me.testNode.getValue(); 
    overheat = overheat ? overheat : me.temperatureNode.getValue() >= me.maxTempNode.getValue();
  }

  me.temperatureNode.setDoubleValue( temp );
  me.overHeatNode.setBoolValue( overheat );
}

####################################################################

var updateClients = [];

var timeNode = props.globals.getNode( "/sim/time/elapsed-sec", 1 );
var lastRun = timeNode.getValue();

var HansajetTimer = func {

  foreach( var updateClient; updateClients ) {
    var dt = timeNode.getValue() - lastRun;
    updateClient.update(dt);
  }

  lastRun = timeNode.getValue();
  settimer( HansajetTimer, 0 );
};

var Dragchute = {
  new : func {
    var obj = {};
    obj.parents = [Dragchute];

    obj.length = aircraft.door.new( "sim/model/Hansajet/Dragchute/length", 0.5 );
    obj.size = aircraft.door.new( "sim/model/Hansajet/Dragchute/size", 1 );
    obj.twist = aircraft.door.new( "sim/model/Hansajet/Dragchute/twist", 2.9 );
    aircraft.light.new( "sim/model/Hansajet/Dragchute/freq", [ 3, 3 ] ).switch(1);
    setlistener( "sim/model/Hansajet/Dragchute/freq/state", func(n) {
      n.getValue() ? obj.twist.open() : obj.twist.close();
    }, 0, 0 );

    obj.dragchuteJett = props.globals.getNode( "instrumentation/annunciator/drag-chute-jett", 1 );
    obj.dragchuteJett.setBoolValue( 0 );

    obj.pack();

    setlistener( "controls/flight/drag-chute", func(n) { obj.chuteListener(n); }, 1, 0 );

    #open the chute if 80 percent extended
    setlistener( "sim/model/Hansajet/Dragchute/length/position-norm", func(n) {
      if( n.getValue() > 0.8 )
        obj.size.open();
    }, 0, 0 );

    return obj;
  },

  chuteListener : func(n) {
    if( n.getValue() and getprop( "instrumentation/annunciator/drag-chute-jett" ) == 0 ) {
      me.dragchuteJett.setBoolValue( 1 );
      me.length.open();
    }
  },

  jettison : func {
  },

  pack : func {
    me.length.setpos( 0.0 );
    me.length.close();
    me.size.setpos( 0.0 );
    me.size.close();
    me.dragchuteJett.setBoolValue( 0 );
    print( "Dragchute packed and ready for use" );
  }
};

var dragchute = nil;

var initialize_fuelsystem = func {
  var n = props.globals.getNode("/systems/fuel");
  n == nil and return;

  foreach( var nn; n.getChildren( "fuel-pump" ) ) {
    append( updateClients, FuelPump.new( nn ) );
  }

  var autoSequencer = [];
  foreach( var nn; n.getChildren( "auto-sequencer" ) )
    append( updateClients, AutoSequencer.new( nn ) );

  setlistener( "/controls/fuel/selected-sequencer", func(n) { 
    var v = n.getValue();
    if( v == nil ) v = 0;
    setprop( "/systems/fuel/auto-sequencer[" ~ v ~ "]/enabled", 1 );
    v = !v;
    setprop( "/systems/fuel/auto-sequencer[" ~ v ~ "]/enabled", 0 );
  }, 1, 0 );

  return;
};

var initialize = func {
  print( "Hansa Jet nasal systems initializing..." );
  var hydraulicSystem = nil;
  var hydraulicElement = nil;
  var hydraulicReservoir = nil;

  hydraulicReservoir = HydraulicReservoir.new( "systems/hydraulic", 0 );

  hydraulicSystem = HydraulicSystem.new( "systems/hydraulic/system", 0 );
  hydraulicSystem.addReservoir( hydraulicReservoir );
  hydraulicElement = HydraulicPump.new( "engines/engine[0]/n2", 25, 4, 100 );
  hydraulicSystem.addPump( hydraulicElement );
  hydraulicElement = HydraulicLoad.new( 5 );
  hydraulicSystem.addLoad( hydraulicElement );
  append( updateClients, hydraulicSystem );

  hydraulicSystem = HydraulicSystem.new( "systems/hydraulic/system", 1 );
  hydraulicSystem.addReservoir( hydraulicReservoir );
  hydraulicElement = HydraulicPump.new( "engines/engine[1]/n2", 25, 4, 100 );
  hydraulicSystem.addPump( hydraulicElement );
  hydraulicElement = HydraulicLoad.new( 2 );
  hydraulicSystem.addLoad( hydraulicElement );
  append( updateClients, hydraulicSystem );

  hydraulicSystem = HydraulicSystem.new( "systems/hydraulic/system", 2 );
  hydraulicSystem.addReservoir( hydraulicReservoir );
  hydraulicElement = HydraulicPump.new( "engines/engine[0]/n2", 25, 4, 20 );
  hydraulicSystem.addPump( hydraulicElement );
  hydraulicElement = HydraulicPump.new( "engines/engine[1]/n2", 25, 4, 20 );
  hydraulicSystem.addPump( hydraulicElement );
  hydraulicElement = HydraulicLoad.new( 1 );
  hydraulicSystem.addLoad( hydraulicElement );
  append( updateClients, hydraulicSystem );

#  append( updateClients, FuelTanks.new(5) );
  append( updateClients, Engines.new(2) );
#  append( updateClients, WindshieldHeater.new( 0 ) );
#  append( updateClients, WindshieldHeater.new( 1 ) );

#  append( updateClients, aircraft.tyresmoke.new(0) );
#  append( updateClients, aircraft.tyresmoke.new(1) );
#  append( updateClients, aircraft.tyresmoke.new(2) );

#  append( updateClients, Wiper.new(0) );
#  append( updateClients, Wiper.new(1) );

  initialize_fuelsystem();  

  dragchute = Dragchute.new();
  MasterCaution.new();
  HansajetTimer();
  print( "Hansa Jet nasal systems initialized" );
};

if( getprop( "sim/presets/onground" ) == 0 ) {
  setprop("sim/presets/running",1);
  setprop("controls/electric/battery[0]", 1 );
  setprop("controls/electric/battery[1]", 1 );
  setprop("systems/fuel/fuel-pump[3]/enabled", 1 );
  setprop("systems/fuel/fuel-pump[5]/enabled", 1 );
  setprop("controls/electric/generator[0]", 1 );
  setprop("controls/electric/generator[1]", 1 );
}

setlistener("/sim/signals/fdm-initialized", initialize );
