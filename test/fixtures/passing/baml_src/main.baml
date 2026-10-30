function clamp(value: int, low: int, high: int) -> int {
    if (value < low) {
        low
    } else if (value > high) {
        high
    } else {
        value
    }
}

function shipping_cost(weight: int, express: bool, international: bool) -> int {
    let cost = weight * 2;
    if (express) {
        cost = cost * 2;
    }
    if (international) {
        cost = cost + 15;
    }
    cost
}

function grade(score: int) -> string {
    if (score >= 90) {
        "A"
    } else if (score >= 80) {
        "B"
    } else if (score >= 70) {
        "C"
    } else if (score >= 60) {
        "D"
    } else {
        "F"
    }
}

function legacy_discount(total: int) -> int {
    if (total > 100) { total - 10 } else { total }
}


test "clamp keeps values in range" {
    assert.equal(clamp(5, 0, 10), 5);
    assert.equal(clamp(-3, 0, 10), 0);
    assert.equal(clamp(42, 0, 10), 10)
}
