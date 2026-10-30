/// The collapsed reference at the end of the comment. Every example's score
/// was checked with `baml codequality`.
///
/// A quoted string rather than a backtick one: the parser's backtick-close
/// lookahead stops at a line starting with `function` and skips `//`, both of
/// which the BAML examples contain.
function explanations() -> string {
    "#### What these mean

<details>
<summary>Cognitive: how hard the function is to follow</summary>

Each branch or loop adds 1, plus 1 more for every level it is nested inside. Deep nesting costs the most.

Scores 7:

```baml
function capped_total(scores: int[]) -> int {
    let total = 0;
    for (let s in scores) {        // +1
        if (s > 0) {               // +2, nested once
            if (s > 100) {         // +3, nested twice
                total += 100;
            } else {               // +1
                total += s;
            }
        }
    }
    total
}
```

Scores 1, with the branching moved into `cap`:

```baml
function capped_total(scores: int[]) -> int {
    let total = 0;
    for (let s in scores) {        // +1
        total += cap(s);
    }
    total
}
```

</details>

<details>
<summary>Cyclomatic: how many decisions the function makes</summary>

1, plus 1 for each `if`, `else if`, loop, `&&` and `||`. Nesting does not matter. Scores 5:

```baml
function shipping(region: string, heavy: bool) -> int {
    if (region == \"us\") {          // +1
        if (heavy) {               // +1
            15
        } else {
            8
        }
    } else if (region == \"eu\") {   // +1
        if (heavy) {               // +1
            20
        } else {
            12
        }
    } else {
        30
    }
}
```

</details>

<details>
<summary>NPath: how many paths a test would need to cover</summary>

Branches in a row multiply. Three independent `if`s give 2 x 2 x 2 = 8 paths, even though cyclomatic is only 4.

```baml
function flags(a: bool, b: bool, c: bool) -> string {
    let s = \"\";
    if (a) {        // x2
        s += \"a\";
    }
    if (b) {        // x2
        s += \"b\";
    }
    if (c) {        // x2
        s += \"c\";
    }
    s
}
```

</details>

<details>
<summary>Nesting: how deep the deepest block goes</summary>

The most blocks open at once. Early returns and helper functions flatten it. Depth 3:

```baml
function total_size(rows: Row[]) -> int {
    let count = 0;
    for (let row in rows) {                // 1
        if (row.active) {                  // 2
            for (let cell in row.cells) {  // 3
                count += cell.size;
            }
        }
    }
    count
}
```

</details>

<details>
<summary>Exits: how many places the function can return</summary>

Each `return` and `throw`, plus the final expression. More exits mean more places to check when reading what a function gives back.

</details>"
}
