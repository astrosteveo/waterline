// A hull scene's surface in the rider's colours, see-through and glowing faintly, for a
// time-trial ghost (JetSkiModel.ghost): see hull_paint.gdshaderinc. Only the front faces are
// drawn, so the inside of the hull doesn't show through.
shader_type spatial;
render_mode cull_back;

#define GHOST
#include "res://jetski/model/hull_paint.gdshaderinc"
