"""Unit tests for the settlement algorithm (no database needed)."""
import itertools
import random

import pytest

from settlement import _greedy, compute_settlements

R = 100  # rupees -> paise


def apply(balances, payments):
    """Return the balances after performing all payments."""
    result = dict(balances)
    for payer, receiver, cents in payments:
        result[payer] += cents
        result[receiver] -= cents
    return result


def max_zero_sum_groups(values):
    """Independent brute force (O(3^n)): maximum number of disjoint zero-sum groups."""
    n = len(values)
    full = (1 << n) - 1
    total = [0] * (1 << n)
    for m in range(1, 1 << n):
        low = (m & -m).bit_length() - 1
        total[m] = total[m & (m - 1)] + values[low]
    best = {0: 0}

    def solve(mask):
        if mask in best:
            return best[mask]
        low = mask & -mask            # the lowest member must belong to some group
        rest = mask ^ low
        res = 0 if total[mask] != 0 else 1   # whole mask as one group
        sub = rest
        while True:
            group = sub | low
            if total[group] == 0:
                res = max(res, 1 + solve(mask ^ group))
            if sub == 0:
                break
            sub = (sub - 1) & rest
        best[mask] = res
        return res

    return solve(full)


def test_spec_example():
    """TC-ALG-01 | Example from the specification | Rahul -1000, Sneha -500, Ishani +1200, Aditi +300 | Rahul->Ishani 1000, Sneha->Ishani 200, Sneha->Aditi 300"""
    ishani, rahul, sneha, aditi = 1, 2, 3, 4
    balances = {ishani: 1200 * R, rahul: -1000 * R, sneha: -500 * R, aditi: 300 * R}
    payments = compute_settlements(balances)
    assert sorted(payments) == sorted([(rahul, ishani, 1000 * R), (sneha, ishani, 200 * R),
                                       (sneha, aditi, 300 * R)])


def test_everyone_square_gives_no_payments():
    """TC-ALG-02 | Nobody owes anything | All balances 0 | No payments"""
    assert compute_settlements({1: 0, 2: 0, 3: 0}) == []
    assert compute_settlements({}) == []


def test_single_pair():
    """TC-ALG-03 | One debtor, one creditor | A -750, B +750 | One payment A->B of 750"""
    assert compute_settlements({1: -75000, 2: 75000}) == [(1, 2, 75000)]


def test_unbalanced_input_is_rejected():
    """TC-ALG-04 | Balances that do not sum to zero | A +100, B -50 | ValueError (data integrity guard)"""
    with pytest.raises(ValueError):
        compute_settlements({1: 10000, 2: -5000})


def test_independent_pairs_are_not_merged():
    """TC-ALG-05 | Two independent debts | A->B 100 and C->D 50 hidden in one trip | Exactly 2 payments, not 3"""
    balances = {1: -10000, 2: 10000, 3: -5000, 4: 5000}
    assert len(compute_settlements(balances)) == 2


def test_exact_search_beats_plain_greedy():
    """TC-ALG-06 | Case where plain greedy is not minimal | -8, +6, -2, +3, +4, -3 | 4 payments (greedy alone needs 5)"""
    balances = {1: -8, 2: 6, 3: -2, 4: 3, 5: 4, 6: -3}
    people = [(u, b) for u, b in balances.items()]
    assert len(_greedy(people)) == 5
    payments = compute_settlements(balances)
    assert len(payments) == 4
    assert all(v == 0 for v in apply(balances, payments).values())


def test_random_balances_are_settled_and_minimal():
    """TC-ALG-07 | 300 random trips (2-8 members) | Random balances summing to 0 | Every balance reaches 0 and the payment count equals the proven minimum"""
    rnd = random.Random(2026)
    for _ in range(300):
        n = rnd.randint(2, 8)
        values = [rnd.randint(-5000, 5000) for _ in range(n - 1)]
        values.append(-sum(values))
        balances = {i + 1: v for i, v in enumerate(values)}
        payments = compute_settlements(balances)
        assert all(v == 0 for v in apply(balances, payments).values())
        assert all(cents > 0 and payer != receiver for payer, receiver, cents in payments)
        nonzero = [v for v in values if v != 0]
        if nonzero:
            assert len(payments) == len(nonzero) - max_zero_sum_groups(nonzero)


def test_large_group_still_settles():
    """TC-ALG-08 | Large group (30 members) uses the greedy fallback | Random balances | Everything is settled with at most n-1 payments"""
    rnd = random.Random(7)
    values = [rnd.randint(-9000, 9000) for _ in range(29)]
    values.append(-sum(values))
    balances = {i + 1: v for i, v in enumerate(values)}
    payments = compute_settlements(balances)
    assert all(v == 0 for v in apply(balances, payments).values())
    assert len(payments) <= 29


def test_result_is_deterministic():
    """TC-ALG-09 | Same input, same output | Run twice with different dict order | Identical payment lists"""
    a = {1: 5000, 2: -2000, 3: -3000, 4: 700, 5: -700}
    b = dict(reversed(list(a.items())))
    assert compute_settlements(a) == compute_settlements(b)
