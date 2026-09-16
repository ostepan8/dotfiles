// Scratch file for the Part 2 drills in LEARN.md.
//
// It has to be a real .cpp file, not the fenced block in LEARN.md: treesitter
// textobjects resolve against the BUFFER's parser, and in a markdown buffer
// that is `markdown`, which has no @function.outer. The C++ inside a fence is
// an injected language and the motions do not see it. See LEARN.md Part 2.
//
// Mangle this freely. `u` undoes, `:e!` restores it from git.

#include <bits/stdc++.h>
using namespace std;

int helper(int a, int b, int c) {
    int sum = a + b;
    return sum + c;
}

long long fib(int n) {
    if (n <= 1) {
        return n;
    }
    long long prev = 0, cur = 1;
    for (int i = 2; i <= n; i++) {
        long long next = prev + cur;
        prev = cur;
        cur = next;
    }
    return cur;
}

vector<int> evens(const vector<int>& xs) {
    vector<int> out;
    for (int x : xs) {
        if (x % 2 == 0) {
            out.push_back(x);
        }
    }
    return out;
}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);

    int x = helper(1, 2, 3);
    long long f = fib(10);
    vector<int> e = evens({1, 2, 3, 4, 5, 6});

    cout << x << " " << f << " " << e.size() << "\n";
    return 0;
}
