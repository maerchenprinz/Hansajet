#
# A SelectorSwitch links one out of many input properties to
# one output property depending on the value of the (INT)-value of 
# one input property.
# It was designed as a helper function for select switches like rotary
# switches.
#
# usage: SelectorSwitch.new( 
#  "/a-switch-position-property-name",
#  "/a-output-property-name",
#  [ "/a/input/property", "/another/input/property", ... ]" );

var SelectorSwitch = {
  new : func( position, output, input ) {
    var obj = {};
    obj.parents = [SelectorSwitch];
    obj.positionN = props.globals.initNode( position, 0, "INT" );
    obj.outputN = props.globals.getNode( output, 1 );
    obj.inputNodes = [];
    
    foreach( var n; input ) {
      append( obj.inputNodes, props.globals.getNode( n, 1 ) );
    }

    setlistener( obj.positionN, func { obj.update(); }, 1, 0 );
    return obj;
  },

  update : func {
    var input = me.inputNodes[ me.positionN.getValue() ];
    me.outputN.unalias();
    me.outputN.alias( input );
  }
};
