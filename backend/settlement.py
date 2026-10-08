"""Settlement algorithm - "who pays whom?".

Input : net balance per member in integer cents (positive = should receive,
        negative = owes). The balances of a trip always add up to zero.
Output: a list of (payer_id, receiver_id, cents) payments that bring every balance to 0.

Strategy
--------
1. Only the *net* balances matter, so individual expenses are never turned into
   repayments.
2. The minimum possible number of payments is  (people with a non-zero balance) minus
   (the maximum number of disjoint groups whose balances add up to zero), because a
   zero-sum group of k people can always be settled with k-1 payments and no fewer.
   Finding that maximum is a bitmask DP, O(n * 2^n), used for groups of up to
   EXACT_LIMIT people, so the result is provably minimal for normal trips.
3. Inside each zero-sum group the largest debtor pays the largest creditor
   (greedy, using a max-heap). For bigger groups (> EXACT_LIMIT) the DP is skipped and
   the greedy method is applied directly: still correct, at most n-1 payments, but
   not guaranteed to be the absolute minimum.
"""
import heapq

EXACT_LIMIT = 14


def compute_settlements(balances):
    """balances: {user_id: cents}. Returns [(payer_id, receiver_id, cents), ...]."""
    if sum(balances.values()) != 0:
        raise ValueError("Balances must add up to zero")
    people = sorted((uid, bal) for uid, bal in balances.items() if bal != 0)
    if not people:
        return []
    if len(people) <= EXACT_LIMIT:
        groups = _zero_sum_groups(people)
    else:
        groups = _pair_exact_matches(people)
    payments = []
    for group in groups:
        payments.extend(_greedy(group))
    return payments


def _zero_sum_groups(people):
    """Split `people` into the largest possible number of zero-sum groups."""
    n = len(people)
    values = [bal for _, bal in people]
    full = (1 << n) - 1

    sums = [0] * (1 << n)
    for mask in range(1, 1 << n):
        low = (mask & -mask).bit_length() - 1
        sums[mask] = sums[mask & (mask - 1)] + values[low]

    dp = [0] * (1 << n)
    parent = [-1] * (1 << n)
    for mask in range(1, 1 << n):
        best = -1
        for i in range(n):
            if mask & (1 << i) and dp[mask ^ (1 << i)] > best:
                best = dp[mask ^ (1 << i)]
                parent[mask] = i
        dp[mask] = best + (1 if sums[mask] == 0 else 0)

    # walk the chain of masks back from the full set; every time the running sum hits
    # zero a group ends.
    order = []
    mask = full
    while mask:
        i = parent[mask]
        order.append(i)
        mask ^= 1 << i
    order.reverse()

    groups, current, running = [], [], 0
    for i in order:
        current.append(people[i])
        running += values[i]
        if running == 0:
            groups.append(current)
            current = []
    return groups


def _pair_exact_matches(people):
    """Cheap pre-pass for big groups: a debtor owing exactly what a creditor is owed."""
    creditors, debtors, groups = {}, {}, []
    for uid, bal in people:
        (creditors if bal > 0 else debtors).setdefault(abs(bal), []).append((uid, bal))
    rest = []
    for amount in sorted(set(creditors) | set(debtors)):
        c, d = creditors.get(amount, []), debtors.get(amount, [])
        while c and d:
            groups.append([c.pop(), d.pop()])
        rest.extend(c + d)
    if rest:
        groups.append(rest)
    return groups


def _greedy(group):
    creditors = [(-bal, uid) for uid, bal in group if bal > 0]
    debtors = [(bal, uid) for uid, bal in group if bal < 0]  # bal is negative => largest debt first
    heapq.heapify(creditors)
    heapq.heapify(debtors)
    payments = []
    while creditors and debtors:
        neg_credit, receiver = heapq.heappop(creditors)
        neg_debt, payer = heapq.heappop(debtors)
        credit, debt = -neg_credit, -neg_debt
        pay = min(credit, debt)
        payments.append((payer, receiver, pay))
        if credit > pay:
            heapq.heappush(creditors, (-(credit - pay), receiver))
        if debt > pay:
            heapq.heappush(debtors, (-(debt - pay), payer))
    return payments
