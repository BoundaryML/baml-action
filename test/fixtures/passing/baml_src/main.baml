function clamp(value: int, low: int, high: int) -> int {
    if (value < low) {
        low
    } else if (value > high) {
        high
    } else {
        value
    }
}

function shipping_cost(weight: int, express: bool, international: bool, members: int[]) -> int {
    let cost = weight * 2;
    if (express) {
        if (international) {
            cost = cost * 3;
        } else {
            cost = cost * 2;
        }
    }
    for (let m in members) {
        if (m > 0) {
            if (cost > 10) {
                cost = cost - 1;
            }
        }
    }
    if (international && weight > 20) {
        cost = cost + 15;
    }
    cost
}

function grade(score: int) -> string {
    if (score >= 60) { "pass" } else { "fail" }
}

function total_weight(weights: int[]) -> int {
    let total = 0;
    for (let w in weights) {
        if (w > 0) {
            total = total + w;
        }
    }
    total
}


test "clamp keeps values in range" {
    assert.equal(clamp(5, 0, 10), 5);
    assert.equal(clamp(-3, 0, 10), 0);
    assert.equal(clamp(42, 0, 10), 10)
}
