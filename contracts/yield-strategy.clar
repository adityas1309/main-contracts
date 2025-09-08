;; Arcadia Yield Strategy Contract
;; Manages yield generation from collateral assets (sBTC staking, etc.)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_STRATEGY (err u402))
(define-constant ERR_INSUFFICIENT_BALANCE (err u403))
(define-constant ERR_STRATEGY_NOT_ACTIVE (err u404))

;; Data Variables
(define-data-var total-assets-under-management uint u0)
(define-data-var default-strategy-id uint u1)
(define-data-var strategy-counter uint u0)

;; Yield Strategies
(define-map yield-strategies
    { strategy-id: uint }
    {
        name: (string-ascii 50),
        description: (string-ascii 200),
        target-apy: uint,           ;; in basis points
        risk-level: uint,           ;; 1-10 scale
        min-deposit: uint,
        max-deposit: uint,
        active: bool,
        total-deposited: uint,
        total-earned: uint,
        last-updated: uint
    }
)

;; User deposits in strategies
(define-map strategy-deposits
    { strategy-id: uint, user: principal }
    {
        amount: uint,
        entry-block: uint,
        last-claim-block: uint,
        total-claimed: uint
    }
)

;; Strategy performance tracking
(define-map strategy-performance
    { strategy-id: uint, period: uint } ;; period = block height / 1000 for daily tracking
    {
        period-start: uint,
        period-end: uint,
        starting-balance: uint,
        ending-balance: uint,
        yield-generated: uint,
        actual-apy: uint
    }
)

;; Loan yield allocations
(define-map loan-yield-allocations
    { loan-id: uint }
    {
        strategy-id: uint,
        allocated-amount: uint,
        accrued-yield: uint,
        last-compound-block: uint
    }
)

;; --- STRATEGY MANAGEMENT ---

;; Initialize default strategies
(define-public (initialize-strategies)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        ;; Strategy 1: Stacks Staking (Conservative)
        (try! (create-strategy 
            "Stacks Staking"
            "Conservative sBTC staking strategy with ~8% APY"
            u800      ;; 8% APY
            u3        ;; Risk level 3/10
            u1000000  ;; 1 STX minimum
            u100000000000 ;; 100k STX maximum
        ))
        
        ;; Strategy 2: DeFi Yield Farming (Moderate)
        (try! (create-strategy
            "DeFi Yield Farming"
            "Moderate risk yield farming across Stacks DeFi protocols"
            u1200     ;; 12% APY
            u6        ;; Risk level 6/10
            u5000000  ;; 5 STX minimum
            u50000000000 ;; 50k STX maximum
        ))
        
        ;; Strategy 3: Liquidity Provision (Aggressive)
        (try! (create-strategy
            "LP Strategy"
            "High-yield liquidity provision with higher volatility"
            u1800     ;; 18% APY
            u8        ;; Risk level 8/10
            u10000000 ;; 10 STX minimum
            u25000000000 ;; 25k STX maximum
        ))
        
        (ok true)))

;; Create new yield strategy
(define-public (create-strategy
    (name (string-ascii 50))
    (description (string-ascii 200))
    (target-apy uint)
    (risk-level uint)
    (min-deposit uint)
    (max-deposit uint))
    (let ((strategy-id (+ (var-get strategy-counter) u1)))
        
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= risk-level u10) ERR_INVALID_STRATEGY)
        
        (map-set yield-strategies
            { strategy-id: strategy-id }
            {
                name: name,
                description: description,
                target-apy: target-apy,
                risk-level: risk-level,
                min-deposit: min-deposit,
                max-deposit: max-deposit,
                active: true,
                total-deposited: u0,
                total-earned: u0,
                last-updated: stacks-block-height
            })
        
        (var-set strategy-counter strategy-id)
        
        (ok strategy-id)))

;; --- YIELD GENERATION ---

;; Allocate loan collateral to yield strategy
(define-public (allocate-to-strategy (loan-id uint) (strategy-id uint) (amount uint))
    (let ((strategy (unwrap! (map-get? yield-strategies { strategy-id: strategy-id }) ERR_INVALID_STRATEGY)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        (asserts! (get active strategy) ERR_STRATEGY_NOT_ACTIVE)
        (asserts! (>= amount (get min-deposit strategy)) ERR_INSUFFICIENT_BALANCE)
        (asserts! (<= amount (get max-deposit strategy)) ERR_INSUFFICIENT_BALANCE)
        
        ;; Record allocation
        (map-set loan-yield-allocations
            { loan-id: loan-id }
            {
                strategy-id: strategy-id,
                allocated-amount: amount,
                accrued-yield: u0,
                last-compound-block: stacks-block-height
            })
        
        ;; Update strategy totals
        (map-set yield-strategies
            { strategy-id: strategy-id }
            (merge strategy { 
                total-deposited: (+ (get total-deposited strategy) amount),
                last-updated: stacks-block-height
            }))
        
        ;; Update total AUM
        (var-set total-assets-under-management 
            (+ (var-get total-assets-under-management) amount))
        
        (ok amount)))

;; Calculate and compound yield for a loan
(define-public (compound-loan-yield (loan-id uint))
    (let ((allocation (unwrap! (map-get? loan-yield-allocations { loan-id: loan-id }) ERR_UNAUTHORIZED))
          (strategy-id (get strategy-id allocation))
          (strategy (unwrap! (map-get? yield-strategies { strategy-id: strategy-id }) ERR_INVALID_STRATEGY)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        
        ;; Calculate yield since last compound
        (let ((blocks-elapsed (- stacks-block-height (get last-compound-block allocation)))
              (allocated-amount (get allocated-amount allocation))
              (target-apy (get target-apy strategy))
              (new-yield (calculate-yield-earned allocated-amount target-apy blocks-elapsed)))
            
            ;; Update allocation with new yield
            (map-set loan-yield-allocations
                { loan-id: loan-id }
                (merge allocation {
                    accrued-yield: (+ (get accrued-yield allocation) new-yield),
                    last-compound-block: stacks-block-height
                }))
            
            ;; Update strategy performance
            (map-set yield-strategies
                { strategy-id: strategy-id }
                (merge strategy {
                    total-earned: (+ (get total-earned strategy) new-yield),
                    last-updated: stacks-block-height
                }))
            
            (ok new-yield))))

;; Harvest yield for loan payment
(define-public (harvest-yield-for-loan (loan-id uint))
    (let ((allocation (unwrap! (map-get? loan-yield-allocations { loan-id: loan-id }) ERR_UNAUTHORIZED))
          (harvestable-yield (get accrued-yield allocation)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        (asserts! (> harvestable-yield u0) ERR_INSUFFICIENT_BALANCE)
        
        ;; Reset accrued yield
        (map-set loan-yield-allocations
            { loan-id: loan-id }
            (merge allocation { accrued-yield: u0 }))
        
        ;; Return yield to Arcadia Protocol for loan payment
        (ok harvestable-yield)))

;; --- STRATEGY PERFORMANCE TRACKING ---

;; Update strategy performance metrics
(define-public (update-strategy-performance (strategy-id uint))
    (let ((strategy (unwrap! (map-get? yield-strategies { strategy-id: strategy-id }) ERR_INVALID_STRATEGY))
          (current-period (/ stacks-block-height u1000))) ;; Daily periods
        
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        ;; Calculate actual APY based on performance
        (let ((total-deposited (get total-deposited strategy))
              (total-earned (get total-earned strategy))
              (actual-apy (if (> total-deposited u0)
                             (/ (* total-earned u10000) total-deposited)
                             u0)))
            
            ;; Record performance for this period
            (map-set strategy-performance
                { strategy-id: strategy-id, period: current-period }
                {
                    period-start: (* current-period u1000),
                    period-end: (+ (* current-period u1000) u1000),
                    starting-balance: total-deposited,
                    ending-balance: (+ total-deposited total-earned),
                    yield-generated: total-earned,
                    actual-apy: actual-apy
                })
            
            (ok actual-apy))))

;; --- UTILITY FUNCTIONS ---

;; Calculate yield earned over a period
(define-read-only (calculate-yield-earned (principal-amount uint) (apy-basis-points uint) (blocks-elapsed uint))
    (let ((annual-yield (/ (* principal-amount apy-basis-points) u10000))
          (blocks-per-year u525600) ;; Approximate blocks in a year (10 min blocks)
          (yield-per-block (/ annual-yield blocks-per-year))
          (total-yield (* yield-per-block blocks-elapsed)))
        total-yield))

;; Get optimal strategy for risk tolerance
(define-read-only (get-optimal-strategy (risk-tolerance uint) (deposit-amount uint))
    (let ((conservative-strategy u1)
          (moderate-strategy u2)
          (aggressive-strategy u3))
        (if (<= risk-tolerance u4)
            (ok conservative-strategy)
            (if (<= risk-tolerance u7)
                (ok moderate-strategy)
                (ok aggressive-strategy)))))

;; --- READ-ONLY FUNCTIONS ---

(define-read-only (get-strategy (strategy-id uint))
    (map-get? yield-strategies { strategy-id: strategy-id }))

(define-read-only (get-loan-allocation (loan-id uint))
    (map-get? loan-yield-allocations { loan-id: loan-id }))

(define-read-only (get-strategy-performance (strategy-id uint) (period uint))
    (map-get? strategy-performance { strategy-id: strategy-id, period: period }))

(define-read-only (get-total-aum)
    (var-get total-assets-under-management))

(define-read-only (calculate-projected-yield (loan-id uint) (future-blocks uint))
    (match (map-get? loan-yield-allocations { loan-id: loan-id })
        allocation (let ((strategy-id (get strategy-id allocation))
                        (allocated-amount (get allocated-amount allocation)))
                      (match (map-get? yield-strategies { strategy-id: strategy-id })
                          strategy (ok (calculate-yield-earned 
                                       allocated-amount 
                                       (get target-apy strategy) 
                                       future-blocks))
                          ERR_INVALID_STRATEGY))
        ERR_UNAUTHORIZED))

(define-read-only (get-all-active-strategies)
    ;; Return list of active strategy IDs
    ;; This is simplified - in practice would iterate through all strategies
    (list u1 u2 u3))

(define-read-only (get-strategy-summary (strategy-id uint))
    (match (map-get? yield-strategies { strategy-id: strategy-id })
        strategy (some {
            strategy-id: strategy-id,
            name: (get name strategy),
            target-apy: (get target-apy strategy),
            risk-level: (get risk-level strategy),
            total-deposited: (get total-deposited strategy),
            total-earned: (get total-earned strategy),
            active: (get active strategy)
        })
        none))

;; --- AUTHORIZATION ---

(define-read-only (is-contract-caller-authorized)
    ;; Check if caller is authorized Arcadia Protocol contract
    (is-eq contract-caller CONTRACT_OWNER))

;; --- ADMIN FUNCTIONS ---

(define-public (pause-strategy (strategy-id uint))
    (let ((strategy (unwrap! (map-get? yield-strategies { strategy-id: strategy-id }) ERR_INVALID_STRATEGY)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set yield-strategies
            { strategy-id: strategy-id }
            (merge strategy { active: false }))
        
        (ok true)))

(define-public (resume-strategy (strategy-id uint))
    (let ((strategy (unwrap! (map-get? yield-strategies { strategy-id: strategy-id }) ERR_INVALID_STRATEGY)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set yield-strategies
            { strategy-id: strategy-id }
            (merge strategy { active: true }))
        
        (ok true)))

(define-public (update-strategy-apy (strategy-id uint) (new-apy uint))
    (let ((strategy (unwrap! (map-get? yield-strategies { strategy-id: strategy-id }) ERR_INVALID_STRATEGY)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set yield-strategies
            { strategy-id: strategy-id }
            (merge strategy { target-apy: new-apy, last-updated: stacks-block-height }))
        
        (ok new-apy)))