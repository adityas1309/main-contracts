;; Arcadia Protocol - Core Contract
;; The foundational economic layer for tokenized real-world assets

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u402))
(define-constant ERR_LOAN_NOT_FOUND (err u403))
(define-constant ERR_INVALID_AMOUNT (err u404))
(define-constant ERR_LOAN_ALREADY_EXISTS (err u405))
(define-constant ERR_INSUFFICIENT_STABILITY_POOL (err u406))

;; Data Variables
(define-data-var loan-counter uint u0)
(define-data-var protocol-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var min-collateral-ratio uint u15000) ;; 150% in basis points
(define-data-var liquidation-threshold uint u12000) ;; 120% in basis points

;; Data Maps
(define-map loans
    { loan-id: uint }
    {
        borrower: principal,
        collateral-amount: uint,
        loan-amount: uint,
        asset-nft-id: uint,
        created-at: uint,
        yield-enabled: bool,
        stability-protection: bool,
        monthly-payment: uint,
        remaining-balance: uint
    }
)

(define-map user-loans principal (list 50 uint))
(define-map collateral-vaults { loan-id: uint } { locked-amount: uint, yield-earned: uint })
(define-map asset-registry { asset-id: uint } { asset-type: (string-ascii 50), verified: bool, value: uint })

;; Stability Pool
(define-data-var stability-pool-balance uint u0)
(define-map stability-contributors principal uint)

;; Yield Strategies (simplified for MVP)
(define-data-var total-staked-sbtc uint u0)
(define-data-var current-yield-rate uint u800) ;; 8% APY in basis points

;; Events
(define-data-var last-event-id uint u0)

;; --- CORE LOAN FUNCTIONS ---

;; Create a new loan with sBTC collateral
(define-public (create-loan 
    (collateral-amount uint)
    (loan-amount uint)
    (asset-nft-id uint)
    (asset-type (string-ascii 50))
    (enable-yield bool)
    (monthly-payment uint))
    (let (
        (loan-id (+ (var-get loan-counter) u1))
        (collateral-ratio (/ (* collateral-amount u10000) loan-amount))
        (current-block stacks-block-height)
    )
    (asserts! (>= collateral-ratio (var-get min-collateral-ratio)) ERR_INSUFFICIENT_COLLATERAL)
    (asserts! (> collateral-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> loan-amount u0) ERR_INVALID_AMOUNT)
    
    ;; Lock collateral in vault
    (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))
    
    ;; Register asset NFT
    (map-set asset-registry 
        { asset-id: asset-nft-id }
        { asset-type: asset-type, verified: true, value: loan-amount })
    
    ;; Create loan record
    (map-set loans
        { loan-id: loan-id }
        {
            borrower: tx-sender,
            collateral-amount: collateral-amount,
            loan-amount: loan-amount,
            asset-nft-id: asset-nft-id,
            created-at: current-block,
            yield-enabled: enable-yield,
            stability-protection: true,
            monthly-payment: monthly-payment,
            remaining-balance: loan-amount
        })
    
    ;; Setup collateral vault
    (map-set collateral-vaults
        { loan-id: loan-id }
        { locked-amount: collateral-amount, yield-earned: u0 })
    
    ;; Update user's loan list
    (let ((current-loans (default-to (list) (map-get? user-loans tx-sender))))
        (map-set user-loans tx-sender (unwrap-panic (as-max-len? (append current-loans loan-id) u50))))
    
    ;; If yield enabled, add to staking
    (if enable-yield
        (var-set total-staked-sbtc (+ (var-get total-staked-sbtc) collateral-amount))
        true)
    
    ;; Update counter
    (var-set loan-counter loan-id)
    
    (ok loan-id)))

;; --- YIELD ACCELERATOR ENGINE ---

;; Process yield and apply to loan principal
(define-public (process-yield-payment (loan-id uint))
    (let (
        (loan-data (unwrap! (map-get? loans { loan-id: loan-id }) ERR_LOAN_NOT_FOUND))
        (vault-data (unwrap! (map-get? collateral-vaults { loan-id: loan-id }) ERR_LOAN_NOT_FOUND))
        (yield-amount (calculate-yield-earned (get locked-amount vault-data)))
    )
    ;; BEGIN block groups all the following statements into one expression.
    (begin
        (asserts! (get yield-enabled loan-data) ERR_UNAUTHORIZED)
        
        (let ((new-balance (if (>= yield-amount (get remaining-balance loan-data))
                              u0
                              (- (get remaining-balance loan-data) yield-amount))))
            
            ;; This inner BEGIN is needed because the inner let also has multiple statements.
            (begin
                ;; Update loan with new balance
                (map-set loans
                    { loan-id: loan-id }
                    (merge loan-data { remaining-balance: new-balance }))
                
                ;; Update vault with yield earned
                (map-set collateral-vaults
                    { loan-id: loan-id }
                    (merge vault-data { yield-earned: (+ (get yield-earned vault-data) yield-amount) }))
                
                ;; If loan is paid off, release collateral and NFT
                (try! (if (is-eq new-balance u0)
                    (complete-loan loan-id)
                    (ok true)))
            )
        )
        
        ;; This is now the final statement inside the main BEGIN block.
        (ok yield-amount)
    )))
    

;; Calculate yield earned on collateral
(define-read-only (calculate-yield-earned (collateral-amount uint))
    (let (
        (annual-yield (/ (* collateral-amount (var-get current-yield-rate)) u10000))
        (blocks-per-year u52560) ;; Approximate blocks in a year
        (yield-per-block (/ annual-yield blocks-per-year))
    )
    yield-per-block))

;; --- STABILITY & INSURANCE POOL ---

;; Contribute to stability pool
(define-public (contribute-to-stability-pool (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set stability-pool-balance (+ (var-get stability-pool-balance) amount))
        (map-set stability-contributors tx-sender 
            (+ amount (default-to u0 (map-get? stability-contributors tx-sender))))
        (ok amount)))

;; Guardian function - make payment from stability pool
(define-public (guardian-payment (loan-id uint) (payment-amount uint))
    (let (
        (loan-data (unwrap! (map-get? loans { loan-id: loan-id }) ERR_LOAN_NOT_FOUND))
        (current-pool (var-get stability-pool-balance))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED) ;; Only protocol can call
    (asserts! (>= current-pool payment-amount) ERR_INSUFFICIENT_STABILITY_POOL)
    (asserts! (get stability-protection loan-data) ERR_UNAUTHORIZED)
    
    ;; Deduct from stability pool
    (var-set stability-pool-balance (- current-pool payment-amount))
    
    ;; Apply payment to loan
    (let ((new-balance (- (get remaining-balance loan-data) payment-amount)))
        (map-set loans
            { loan-id: loan-id }
            (merge loan-data { remaining-balance: new-balance })))
    
    (ok payment-amount)))

;; --- LOAN COMPLETION & NFT TRANSFER ---

;; Complete loan and transfer ownership NFT
(define-public (complete-loan (loan-id uint))
    (let (
        (loan-data (unwrap! (map-get? loans { loan-id: loan-id }) ERR_LOAN_NOT_FOUND))
        (vault-data (unwrap! (map-get? collateral-vaults { loan-id: loan-id }) ERR_LOAN_NOT_FOUND))
    )
    (asserts! (is-eq (get remaining-balance loan-data) u0) ERR_UNAUTHORIZED)
    
    ;; Release collateral back to borrower
    (try! (as-contract (stx-transfer? (get locked-amount vault-data) tx-sender (get borrower loan-data))))
    
    ;; TODO: Transfer ownership NFT to borrower
    ;; This would integrate with the asset NFT contract
    
    ;; Clean up maps
    (map-delete loans { loan-id: loan-id })
    (map-delete collateral-vaults { loan-id: loan-id })
    
    (ok true)))

;; --- ANT TOKEN MINTING (Arcadia Note Tokens) ---

;; Mint ANT tokens for secondary market
(define-public (mint-ant-token (loan-id uint) (recipient principal))
    (let (
        (loan-data (unwrap! (map-get? loans { loan-id: loan-id }) ERR_LOAN_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    ;; TODO: Implement ANT token minting logic
    ;; This would create a yield-bearing token representing the loan
    
    (ok true)))

;; --- READ-ONLY FUNCTIONS ---

(define-read-only (get-loan (loan-id uint))
    (map-get? loans { loan-id: loan-id }))

(define-read-only (get-user-loans (user principal))
    (map-get? user-loans user))

(define-read-only (get-collateral-vault (loan-id uint))
    (map-get? collateral-vaults { loan-id: loan-id }))

(define-read-only (get-stability-pool-balance)
    (var-get stability-pool-balance))

(define-read-only (calculate-collateral-ratio (loan-id uint))
    (match (map-get? loans { loan-id: loan-id })
        loan-data (ok (/ (* (get collateral-amount loan-data) u10000) (get remaining-balance loan-data)))
        ERR_LOAN_NOT_FOUND))

(define-read-only (get-protocol-stats)
    {
        total-loans: (var-get loan-counter),
        total-staked: (var-get total-staked-sbtc),
        stability-pool: (var-get stability-pool-balance),
        current-yield-rate: (var-get current-yield-rate)
    })

;; --- ADMIN FUNCTIONS ---

(define-public (set-yield-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set current-yield-rate new-rate)
        (ok new-rate)))

(define-public (set-collateral-ratio (new-ratio uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set min-collateral-ratio new-ratio)
        (ok new-ratio)))