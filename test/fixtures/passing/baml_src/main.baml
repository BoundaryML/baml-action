function clamp(value: int, low: int, high: int) -> int {
    value.clamp(low, high)
}

function express_multiplier(express: bool, international: bool) -> int {
    if (!express) {
        return 1;
    }
    match (international) {
        true => 3,
        false => 2,
    }
}

function shipping_cost(weight: int, express: bool, international: bool, members: int[]) -> int {
    let cost = weight * 2 * express_multiplier(express, international);
    for (let m in members) {
        if (m > 0) {
            if (cost > 10) {
                if (m > 100 && !international) {
                    cost = cost - 2;
                } else {
                    cost = cost - 1;
                }
            }
        }
    }
    if (international && weight > 20) {
        cost = cost + 15;
    } else if (international || weight > 50) {
        cost = cost + 5;
    }
    cost
}

test "clamp keeps values in range" {
    assert.equal(clamp(5, 0, 10), 5);
    assert.equal(clamp(-3, 0, 10), 0);
    assert.equal(clamp(42, 0, 10), 10)
}

test "shipping cost" {
    assert.equal(shipping_cost(10, true, true, [1, 2]), 63);
    assert.equal(shipping_cost(30, false, true, []), 75);
    assert.equal(shipping_cost(3, false, false, [5]), 6)
}
