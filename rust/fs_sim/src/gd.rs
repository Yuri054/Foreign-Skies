//! The few Godot math functions the simulation uses, written the way Godot writes them so that results agree to the bit.

/// Godot's `lerpf`: `from + (to - from) * weight`.
pub fn lerpf(from: f64, to: f64, weight: f64) -> f64 {
    from + (to - from) * weight
}

/// Godot's `inverse_lerp`: `(weight - from) / (to - from)`.
pub fn inverse_lerp(from: f64, to: f64, weight: f64) -> f64 {
    (weight - from) / (to - from)
}

/// Godot's `clampf`: below the minimum is the minimum, above the maximum is the maximum.
pub fn clampf(value: f64, min: f64, max: f64) -> f64 {
    if value < min {
        min
    } else if value > max {
        max
    } else {
        value
    }
}

/// Godot's `maxf`: `a > b ? a : b`.
pub fn maxf(a: f64, b: f64) -> f64 {
    if a > b {
        a
    } else {
        b
    }
}

/// Godot's `minf`: `a < b ? a : b`.
pub fn minf(a: f64, b: f64) -> f64 {
    if a < b {
        a
    } else {
        b
    }
}
