// The deep seabed: doesn't receive shadows (a craft's shadow 15 m down shows through the
// water as a smudge). See terrain.gdshaderinc.
shader_type spatial;
render_mode shadows_disabled;

#include "res://environment/terrain.gdshaderinc"
