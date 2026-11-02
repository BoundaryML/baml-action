function clamp(value: int, low: int, high: int) -> int {
    value.clamp(low, high)
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

test "clamp keeps values in range" {
    assert.equal(clamp(5, 0, 10), 5);
    assert.equal(clamp(-3, 0, 10), 0);
    assert.equal(clamp(42, 0, 10), 10)
}

test "shipping cost" {
    assert.equal(shipping_cost(10, true, true, [1, 2]), 58);
    assert.equal(shipping_cost(30, false, true, []), 75);
    assert.equal(shipping_cost(3, false, false, [5]), 6)
}
