package main;

import "core:math";
import "core:math/linalg";

// #todo do I really this these? The zero thing for sure no just use 0.
VEC3_ZERO    :: linalg.Vector3f32 { 0,  0,  0};
VEC3_ONE     :: linalg.Vector3f32 { 1,  1,  1};
VEC3_NEG_ONE :: linalg.Vector3f32 {-1, -1, -1};
VEC3_INF     :: linalg.Vector3f32 { math.INF_F32,  math.INF_F32,  math.INF_F32};
VEC3_NEG_INF :: linalg.Vector3f32 {-math.INF_F32, -math.INF_F32, -math.INF_F32};