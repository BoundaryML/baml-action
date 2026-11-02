function clamp(value: int, low: int, high: int) -> int {
    if (value < low) {
        low
    } else {
        value
    }
}

test "clamp caps at high" {
    assert.equal(clamp(42, 0, 10), 10)
}
