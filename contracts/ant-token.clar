;; Arcadia Note Token (ANT) Contract
;; Yield-bearing tokens representing loan cash flows for secondary market trading

;; Implement SIP-010 Fungible Token Standard
(impl-trait .sip-010-ft-trait.sip-010-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INSUFFICIENT_BALANCE (err u402))
(define-constant ERR_TOKEN_NOT_FOUND (err u403))
(define-constant ERR_INVALID_AMOUNT (err u404))
(define-constant ERR_LOAN_NOT_ACTIVE (err u405))

;; Token Definition
(define-fungible-token arcadia-note-token)

;; Data Variables
(define-data-var token-name (string-ascii 32) "Arcadia Note Token")
(define-data-var token-symbol (string-ascii 32) "ANT")
(define-data-var token-decimals uint u6)
(define-data-var next-series-id uint u1)

;; Token Series Data (each loan creates a series of ANTs)
(define-map token-series
    { series-id: uint }
    {
        loan-id: uint,
        original-principal: uint,
        remaining-principal: uint,
        monthly-payment: uint,
        interest-rate: uint,
        maturity-date: uint,
        asset-type: (string-ascii 50),
        risk-rating: (string-ascii 10),
        created-at: uint,
        total-supply: uint,
        yield-distributed: uint
    }
)

;; User holdings per series
(define-map series-balances
    { series-id: uint, holder: principal }
    { balance: uint, last-claim-block: uint }
)

;; Series ownership tracking
(define-map user-series principal (list 100 uint))

;; Yield distribution tracking
(define-map yield-pool { series-id: uint } { available-yield: uint, distributed-yield: uint })
(define-map cumulative-yield-per-token { series-id: uint } uint)

;; Market data
(define-map series-market-data
    { series-id: uint }
    {
        last-trade-price: uint,
        volume-24h: uint,
        total-volume: uint,
        active-orders: uint
    }
)

;; --- SIP-010 IMPLEMENTATION ---

(define-read-only (get-name)
    (ok (var-get token-name)))

(define-read-only (get-symbol)
    (ok (var-get token-symbol)))

(define-read-only (get-decimals)
    (ok (var-get token-decimals)))

(define-read-only (get-balance (who principal))
    (ok (ft-get-balance arcadia-note-token who)))

(define-read-only (get-total-supply)
    (ok (ft-get-supply arcadia-note-token)))

(define-read-only (get-token-uri)
    (ok none))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) ERR_UNAUTHORIZED)
        (ft-transfer? arcadia-note-token amount sender recipient)))

;; --- ANT SERIES MANAGEMENT ---

;; Create new ANT series for a loan
(define-public (create-ant-series 
    (loan-id uint)
    (principal-amount uint)
    (monthly-payment uint)
    (interest-rate uint)
    (maturity-blocks uint)
    (asset-type (string-ascii 50))
    (risk-rating (string-ascii 10)))
    (let ((series-id (var-get next-series-id)))
        
        ;; Only Arcadia Protocol can create series
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        
        ;; Create series data
        (map-set token-series
            { series-id: series-id }
            {
                loan-id: loan-id,
                original-principal: principal-amount,
                remaining-principal: principal-amount,
                monthly-payment: monthly-payment,
                interest-rate: interest-rate,
                maturity-date: (+ stacks-block-height maturity-blocks),
                asset-type: asset-type,
                risk-rating: risk-rating,
                created-at: stacks-block-height,
                total-supply: u0,
                yield-distributed: u0
            })
        
        ;; Initialize yield pool
        (map-set yield-pool
            { series-id: series-id }
            { available-yield: u0, distributed-yield: u0 })
        
        ;; Initialize market data
        (map-set series-market-data
            { series-id: series-id }
            {
                last-trade-price: u1000000, ;; Start at par (1.0 in 6 decimals)
                volume-24h: u0,
                total-volume: u0,
                active-orders: u0
            })
        
        ;; Update counter
        (var-set next-series-id (+ series-id u1))
        
        (ok series-id)))

;; Mint ANT tokens to investors
(define-public (mint-ant-tokens (series-id uint) (recipient principal) (amount uint))
    (let ((series-data (unwrap! (map-get? token-series { series-id: series-id }) ERR_TOKEN_NOT_FOUND)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; Mint the fungible tokens
        (try! (ft-mint? arcadia-note-token amount recipient))
        
        ;; Update series balance for holder
        (let ((current-balance (get-series-balance series-id recipient)))
            (map-set series-balances
                { series-id: series-id, holder: recipient }
                { balance: (+ current-balance amount), last-claim-block: stacks-block-height }))
        
        ;; Add series to user's list if not already there
        (let ((user-series-list (default-to (list) (map-get? user-series recipient))))
            (if (is-none (index-of user-series-list series-id))
                (map-set user-series recipient 
                    (unwrap-panic (as-max-len? (append user-series-list series-id) u100)))
                true))
        
        ;; Update total supply for series
        (map-set token-series
            { series-id: series-id }
            (merge series-data { total-supply: (+ (get total-supply series-data) amount) }))
        
        (ok amount)))

;; --- YIELD DISTRIBUTION SYSTEM ---

;; Add yield to a series (from loan payments)
(define-public (add-yield-to-series (series-id uint) (yield-amount uint))
    (let ((current-pool (unwrap! (map-get? yield-pool { series-id: series-id }) ERR_TOKEN_NOT_FOUND))
          (series-data (unwrap! (map-get? token-series { series-id: series-id }) ERR_TOKEN_NOT_FOUND)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        
        ;; Add yield to available pool
        (map-set yield-pool
            { series-id: series-id }
            (merge current-pool { available-yield: (+ (get available-yield current-pool) yield-amount) }))
        
        ;; Update cumulative yield per token
        (let ((total-supply (get total-supply series-data)))
            (if (> total-supply u0)
                (let ((yield-per-token (/ (* yield-amount u1000000) total-supply))
                      (current-cumulative (default-to u0 (map-get? cumulative-yield-per-token { series-id: series-id }))))
                    (map-set cumulative-yield-per-token
                        { series-id: series-id }
                        (+ current-cumulative yield-per-token)))
                true))
        
        (ok yield-amount)))

;; Claim accumulated yield
(define-public (claim-yield (series-id uint))
    (let ((holder-data (unwrap! (map-get? series-balances { series-id: series-id, holder: tx-sender }) ERR_TOKEN_NOT_FOUND))
          (cumulative-yield (default-to u0 (map-get? cumulative-yield-per-token { series-id: series-id })))
          (holder-balance (get balance holder-data)))
        
        ;; Calculate claimable yield
        (let ((total-yield-earned (/ (* holder-balance cumulative-yield) u1000000))
              (last-claimed (get last-claim-block holder-data))
              (claimable-yield (calculate-claimable-yield series-id tx-sender)))
            
            (asserts! (> claimable-yield u0) ERR_INVALID_AMOUNT)
            
            ;; Transfer yield to holder (in STX)
            (try! (as-contract (stx-transfer? claimable-yield tx-sender tx-sender)))
            
            ;; Update last claim block
            (map-set series-balances
                { series-id: series-id, holder: tx-sender }
                (merge holder-data { last-claim-block: stacks-block-height }))
            
            ;; Update distributed yield
            (let ((yield-pool-data (unwrap-panic (map-get? yield-pool { series-id: series-id }))))
                (map-set yield-pool
                    { series-id: series-id }
                    (merge yield-pool-data { 
                        distributed-yield: (+ (get distributed-yield yield-pool-data) claimable-yield),
                        available-yield: (- (get available-yield yield-pool-data) claimable-yield)
                    })))
            
            (ok claimable-yield))))

;; --- SECONDARY MARKET FUNCTIONS ---

;; Create a sell order
(define-public (create-sell-order 
    (series-id uint) 
    (amount uint) 
    (price-per-token uint))
    (let ((holder-balance (get-series-balance series-id tx-sender)))
        
        (asserts! (>= holder-balance amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> price-per-token u0) ERR_INVALID_AMOUNT)
        
        ;; TODO: Implement order book logic
        ;; For now, this is a placeholder for the secondary market
        
        (ok true)))

;; Execute a buy order
(define-public (execute-buy-order 
    (series-id uint) 
    (amount uint) 
    (max-price-per-token uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> max-price-per-token u0) ERR_INVALID_AMOUNT)
        
        ;; TODO: Implement order matching logic
        ;; This would match buy orders with sell orders
        
        (ok true)))

;; Update principal after loan payment
(define-public (update-series-principal (series-id uint) (new-principal uint))
    (let ((series-data (unwrap! (map-get? token-series { series-id: series-id }) ERR_TOKEN_NOT_FOUND)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        
        (map-set token-series
            { series-id: series-id }
            (merge series-data { remaining-principal: new-principal }))
        
        (ok new-principal)))

;; --- READ-ONLY FUNCTIONS ---

(define-read-only (get-series-data (series-id uint))
    (map-get? token-series { series-id: series-id }))

(define-read-only (get-series-balance (series-id uint) (holder principal))
    (default-to u0 (get balance (map-get? series-balances { series-id: series-id, holder: holder }))))

(define-read-only (get-user-series (user principal))
    (map-get? user-series user))

(define-read-only (get-series-yield-data (series-id uint))
    (map-get? yield-pool { series-id: series-id }))

(define-read-only (get-series-market-data (series-id uint))
    (map-get? series-market-data { series-id: series-id }))

(define-read-only (calculate-claimable-yield (series-id uint) (holder principal))
    (let ((holder-data (map-get? series-balances { series-id: series-id, holder: holder }))
          (cumulative-yield (default-to u0 (map-get? cumulative-yield-per-token { series-id: series-id }))))
        (match holder-data
            data (let ((holder-balance (get balance data))
                       (total-earned (/ (* holder-balance cumulative-yield) u1000000)))
                   ;; Simplified calculation - in practice would track already claimed amounts
                   (/ total-earned u10)) ;; Return 10% for demo purposes
            u0)))

(define-read-only (get-series-apy (series-id uint))
    (match (map-get? token-series { series-id: series-id })
        series-data (let ((annual-payments (/ u525600 u4380)) ;; ~12 monthly payments per year
                          (annual-yield (* (get monthly-payment series-data) annual-payments))
                          (principal (get original-principal series-data)))
                        (if (> principal u0)
                            (ok (/ (* annual-yield u10000) principal))
                            (ok u0)))
        ERR_TOKEN_NOT_FOUND))

(define-read-only (get-series-duration-remaining (series-id uint))
    (match (map-get? token-series { series-id: series-id })
        series-data (if (> (get maturity-date series-data) stacks-block-height)
                       (ok (- (get maturity-date series-data) stacks-block-height))
                       (ok u0))
        ERR_TOKEN_NOT_FOUND))

(define-read-only (calculate-series-value (series-id uint))
    (match (map-get? token-series { series-id: series-id })
        series-data (let ((remaining-payments (get remaining-principal series-data))
                          (monthly-payment (get monthly-payment series-data))
                          (time-remaining (unwrap-panic (get-series-duration-remaining series-id))))
                        ;; Simplified NPV calculation
                        (ok (+ remaining-payments (* monthly-payment (/ time-remaining u4380)))))
        ERR_TOKEN_NOT_FOUND))

;; --- UTILITY FUNCTIONS ---

(define-read-only (is-contract-caller-authorized)
    ;; Check if caller is authorized Arcadia Protocol contract
    (is-eq contract-caller CONTRACT_OWNER))

;; --- ADMIN FUNCTIONS ---

(define-public (set-token-metadata 
    (new-name (string-ascii 32))
    (new-symbol (string-ascii 32))
    (new-decimals uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set token-name new-name)
        (var-set token-symbol new-symbol)
        (var-set token-decimals new-decimals)
        (ok true)))

;; Emergency pause function
(define-data-var contract-paused bool false)

(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused true)
        (ok true)))

(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused false)
        (ok true)))

(define-read-only (is-paused)
    (var-get contract-paused))