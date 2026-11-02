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

/// `Array.sort_custom`: Godot's own sort (`SortArray`, an introsort that is not stable), so that elements the comparison calls
/// equal come out in the order the game puts them. `less(a, b)` is the callable's answer.
pub fn sort_custom<T: Clone>(v: &mut [T], less: impl Fn(&T, &T) -> bool) {
    const THRESHOLD: usize = 16;
    fn bitlog(mut n: usize) -> usize {
        let mut k = 0;
        while n != 1 {
            n >>= 1;
            k += 1;
        }
        k
    }
    fn median<T: Clone>(a: &T, b: &T, c: &T, less: &impl Fn(&T, &T) -> bool) -> T {
        if less(a, b) {
            if less(b, c) {
                b.clone()
            } else if less(a, c) {
                c.clone()
            } else {
                a.clone()
            }
        } else if less(a, c) {
            a.clone()
        } else if less(b, c) {
            c.clone()
        } else {
            b.clone()
        }
    }
    fn unguarded_linear_insert<T: Clone>(v: &mut [T], last: usize, less: &impl Fn(&T, &T) -> bool) {
        let val = v[last].clone();
        let mut last = last;
        let mut next = last - 1;
        while less(&val, &v[next]) {
            v[last] = v[next].clone();
            last = next;
            if next == 0 {
                break;
            }
            next -= 1;
        }
        v[last] = val;
    }
    fn linear_insert<T: Clone>(v: &mut [T], first: usize, last: usize, less: &impl Fn(&T, &T) -> bool) {
        let val = v[last].clone();
        if less(&val, &v[first]) {
            for i in (first..last).rev() {
                v[i + 1] = v[i].clone();
            }
            v[first] = val;
        } else {
            unguarded_linear_insert(v, last, less);
        }
    }
    fn insertion_sort<T: Clone>(v: &mut [T], first: usize, last: usize, less: &impl Fn(&T, &T) -> bool) {
        for i in first + 1..last {
            linear_insert(v, first, i, less);
        }
    }
    fn introsort<T: Clone>(v: &mut [T], first: usize, mut last: usize, mut depth: usize, less: &impl Fn(&T, &T) -> bool) {
        while last - first > THRESHOLD {
            if depth == 0 {
                panic!("Godot's sort fell back to a heap sort: not ported");
            }
            depth -= 1;
            let pivot = median(&v[first], &v[first + (last - first) / 2], &v[last - 1], less);
            // the partition
            let (mut f, mut l) = (first, last);
            let cut = loop {
                while less(&v[f], &pivot) {
                    f += 1;
                }
                l -= 1;
                while less(&pivot, &v[l]) {
                    l -= 1;
                }
                if f >= l {
                    break f;
                }
                v.swap(f, l);
                f += 1;
            };
            introsort(v, cut, last, depth, less);
            last = cut;
        }
    }
    let n = v.len();
    if n > 1 {
        introsort(v, 0, n, bitlog(n) * 2, &less);
        if n > THRESHOLD {
            insertion_sort(v, 0, THRESHOLD, &less);
            for i in THRESHOLD..n {
                unguarded_linear_insert(v, i, &less);
            }
        } else {
            insertion_sort(v, 0, n, &less);
        }
    }
}
