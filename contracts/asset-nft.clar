;; Arcadia Asset NFT Contract
;; Tokenizes real-world asset ownership for the Arcadia Protocol

;; Implement SIP-009 NFT Standard
(impl-trait .sip-009-nft-trait.nft-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NFT_NOT_FOUND (err u402))
(define-constant ERR_NOT_OWNER (err u403))
(define-constant ERR_ASSET_NOT_VERIFIED (err u404))
(define-constant ERR_ALREADY_EXISTS (err u405))

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var base-uri (string-ascii 256) "https://api.arcadia.fi/metadata/")

;; NFT Definition
(define-non-fungible-token arcadia-asset uint)

;; Asset Data Structure
(define-map asset-data
    { token-id: uint }
    {
        asset-type: (string-ascii 50),     ;; "home", "vehicle", "art", etc.
        asset-subtype: (string-ascii 50),  ;; "single-family", "condo", "commercial"
        legal-description: (string-utf8 500),
        location: (string-ascii 200),
        verified: bool,
        appraised-value: uint,
        loan-id: (optional uint),          ;; Connected to Arcadia loan
        verification-documents: (string-ascii 500), ;; IPFS hash or similar
        created-at: uint,
        last-updated: uint
    }
)

;; Verification system
(define-map verified-appraisers principal bool)
(define-map asset-verifications 
    { token-id: uint }
    {
        appraiser: principal,
        verification-date: uint,
        verification-hash: (string-ascii 64), ;; Document hash
        next-appraisal-due: uint
    }
)

;; Asset categories and their requirements
(define-map asset-category-config
    { category: (string-ascii 50) }
    {
        min-value: uint,
        max-loan-ratio: uint,              ;; Max LTV in basis points
        verification-period: uint,          ;; Blocks between required verifications
        required-documents: (list 10 (string-ascii 50))
    }
)

;; --- SIP-009 IMPLEMENTATION ---

(define-read-only (get-last-token-id)
    (ok (var-get last-token-id)))

(define-read-only (get-token-uri (token-id uint))
    (ok (some (unwrap-panic (as-max-len? (concat (var-get base-uri) (uint-to-ascii token-id)) u256)))))

(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? arcadia-asset token-id)))

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (let ((current-owner (unwrap! (nft-get-owner? arcadia-asset token-id) ERR_NFT_NOT_FOUND)))
        (asserts! (or (is-eq tx-sender sender) (is-eq tx-sender current-owner)) ERR_NOT_OWNER)
        (nft-transfer? arcadia-asset token-id sender recipient)))

;; --- ASSET MINTING & MANAGEMENT ---

;; Mint new asset NFT (only callable by Arcadia Protocol)
(define-public (mint-asset 
    (recipient principal)
    (asset-type (string-ascii 50))
    (asset-subtype (string-ascii 50))
    (legal-description (string-utf8 500))
    (location (string-ascii 200))
    (appraised-value uint)
    (loan-id (optional uint))
    (verification-docs (string-ascii 500)))
    (let ((token-id (+ (var-get last-token-id) u1)))
        
        ;; Only Arcadia Protocol or authorized minters can mint
        (asserts! (or (is-eq tx-sender CONTRACT_OWNER) 
                     (is-contract-caller-authorized)) ERR_UNAUTHORIZED)
        
        ;; Mint the NFT
        (try! (nft-mint? arcadia-asset token-id recipient))
        
        ;; Store asset data
        (map-set asset-data
            { token-id: token-id }
            {
                asset-type: asset-type,
                asset-subtype: asset-subtype,
                legal-description: legal-description,
                location: location,
                verified: false,
                appraised-value: appraised-value,
                loan-id: loan-id,
                verification-documents: verification-docs,
                created-at: stacks-block-height,
                last-updated: stacks-block-height
            })
        
        ;; Update counter
        (var-set last-token-id token-id)
        
        (ok token-id)))

;; Verify an asset (only by authorized appraisers)
(define-public (verify-asset 
    (token-id uint)
    (new-appraised-value uint)
    (verification-hash (string-ascii 64))
    (verification-period-blocks uint))
    (let ((asset (unwrap! (map-get? asset-data { token-id: token-id }) ERR_NFT_NOT_FOUND)))
        
        (asserts! (default-to false (map-get? verified-appraisers tx-sender)) ERR_UNAUTHORIZED)
        
        ;; Update asset as verified with new value
        (map-set asset-data
            { token-id: token-id }
            (merge asset {
                verified: true,
                appraised-value: new-appraised-value,
                last-updated: stacks-block-height
            }))
        
        ;; Record verification
        (map-set asset-verifications
            { token-id: token-id }
            {
                appraiser: tx-sender,
                verification-date: stacks-block-height,
                verification-hash: verification-hash,
                next-appraisal-due: (+ stacks-block-height verification-period-blocks)
            })
        
        (ok true)))

;; Update asset data (only by owner or Arcadia Protocol)
(define-public (update-asset-data
    (token-id uint)
    (new-appraised-value (optional uint))
    (new-legal-description (optional (string-utf8 500)))
    (new-verification-docs (optional (string-ascii 500))))
    (let ((asset (unwrap! (map-get? asset-data { token-id: token-id }) ERR_NFT_NOT_FOUND))
          (owner (unwrap! (nft-get-owner? arcadia-asset token-id) ERR_NFT_NOT_FOUND)))
        
        (asserts! (or (is-eq tx-sender owner) 
                     (is-eq tx-sender CONTRACT_OWNER)
                     (is-contract-caller-authorized)) ERR_UNAUTHORIZED)
        
        ;; Update fields if provided
        (let ((updated-asset (merge asset {
                appraised-value: (default-to (get appraised-value asset) new-appraised-value),
                legal-description: (default-to (get legal-description asset) new-legal-description),
                verification-documents: (default-to (get verification-documents asset) new-verification-docs),
                last-updated: stacks-block-height
            })))
            (map-set asset-data { token-id: token-id } updated-asset))
        
        (ok true)))

;; Link asset to a loan (only by Arcadia Protocol)
(define-public (link-to-loan (token-id uint) (loan-id uint))
    (let ((asset (unwrap! (map-get? asset-data { token-id: token-id }) ERR_NFT_NOT_FOUND)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        
        (map-set asset-data
            { token-id: token-id }
            (merge asset { loan-id: (some loan-id) }))
        
        (ok true)))

;; Transfer ownership after loan completion
(define-public (complete-ownership-transfer (token-id uint) (new-owner principal))
    (let ((asset (unwrap! (map-get? asset-data { token-id: token-id }) ERR_NFT_NOT_FOUND)))
        
        (asserts! (is-contract-caller-authorized) ERR_UNAUTHORIZED)
        
        ;; Clear loan linkage
        (map-set asset-data
            { token-id: token-id }
            (merge asset { loan-id: none }))
        
        ;; Transfer NFT to new owner
        (nft-transfer? arcadia-asset token-id (as-contract tx-sender) new-owner)))

;; --- ASSET CATEGORY MANAGEMENT ---

;; Configure asset categories (homes, vehicles, art, etc.)
(define-public (configure-asset-category
    (category (string-ascii 50))
    (min-value uint)
    (max-loan-ratio uint)
    (verification-period uint)
    (required-docs (list 10 (string-ascii 50))))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set asset-category-config
            { category: category }
            {
                min-value: min-value,
                max-loan-ratio: max-loan-ratio,
                verification-period: verification-period,
                required-documents: required-docs
            })
        
        (ok true)))

;; --- APPRAISER MANAGEMENT ---

(define-public (authorize-appraiser (appraiser principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set verified-appraisers appraiser true)
        (ok true)))

(define-public (revoke-appraiser (appraiser principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete verified-appraisers appraiser)
        (ok true)))

;; --- READ-ONLY FUNCTIONS ---

(define-read-only (get-asset-data (token-id uint))
    (map-get? asset-data { token-id: token-id }))

(define-read-only (get-asset-verification (token-id uint))
    (map-get? asset-verifications { token-id: token-id }))

(define-read-only (is-appraiser-authorized (appraiser principal))
    (default-to false (map-get? verified-appraisers appraiser)))

(define-read-only (get-category-config (category (string-ascii 50)))
    (map-get? asset-category-config { category: category }))

(define-read-only (is-asset-verified (token-id uint))
    (match (map-get? asset-data { token-id: token-id })
        asset-info (get verified asset-info)
        false))

(define-read-only (needs-reappraisal (token-id uint))
    (match (map-get? asset-verifications { token-id: token-id })
        verification (>= stacks-block-height (get next-appraisal-due verification))
        true)) ;; If never appraised, needs appraisal

;; --- UTILITY FUNCTIONS ---

;; Check if caller is authorized (Arcadia Protocol contract)
(define-read-only (is-contract-caller-authorized)
    ;; This would check if the contract caller is the Arcadia Protocol
    ;; For now, simplified to contract owner check
    (is-eq contract-caller CONTRACT_OWNER))

;; Helper to convert uint to ascii (simplified)
(define-read-only (uint-to-ascii (value uint))
    ;; This is a placeholder - in practice you'd implement proper uint to string conversion
    "placeholder-metadata-uri")

;; --- ADMIN FUNCTIONS ---

(define-public (set-base-uri (new-base-uri (string-ascii 256)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set base-uri new-base-uri)
        (ok true)))

;; Initialize default asset categories
(define-public (initialize-asset-categories)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        ;; Configure homes category
        (try! (configure-asset-category 
            "home"
            u100000000 ;; $100k minimum in microSTX
            u8000      ;; 80% max LTV
            u52560     ;; Annual reappraisal
            (list "deed" "appraisal" "insurance" "survey")))
        
        ;; Configure vehicles category  
        (try! (configure-asset-category
            "vehicle"
            u10000000  ;; $10k minimum
            u7000      ;; 70% max LTV
            u26280     ;; Semi-annual reappraisal
            (list "title" "registration" "appraisal" "insurance")))
        
        ;; Configure art category
        (try! (configure-asset-category
            "art"
            u50000000  ;; $50k minimum
            u6000      ;; 60% max LTV
            u17520     ;; Quarterly reappraisal
            (list "provenance" "appraisal" "insurance" "authenticity")))
        
        (ok true)))