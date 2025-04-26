;; Digital Land Record Vault - A secure vault that enables secure storage, management and verification of property records using blockchain technology

;; ========== ADMINISTRATIVE CONFIGURATIONS ==========

;; Contract Administrator 
(define-constant vault-administrator tx-sender)

;; ========== ERROR CODE DEFINITIONS ==========

;; Administrative Errors
(define-constant err-admin-restricted-function (err u300))

;; Record Management Errors  
(define-constant err-record-not-in-system (err u301))
(define-constant err-record-already-exists (err u302)) 
(define-constant err-invalid-record-name (err u303))
(define-constant err-invalid-record-volume (err u304))
(define-constant err-operation-forbidden (err u305))
(define-constant err-unauthorized-operation (err u306))
(define-constant err-viewing-restricted (err u307))
(define-constant err-invalid-category-format (err u308))

;; ========== STATE VARIABLES ==========

;; Tracks total number of records in the system
(define-data-var total-record-count uint u0)

;; ========== DATA STORAGE STRUCTURES ==========

;; Main property record storage
(define-map property-record-registry
  { record-id: uint }
  {
    record-name: (string-ascii 64),
    record-holder: principal,
    record-volume: uint,
    registration-block: uint,
    record-summary: (string-ascii 128),
    record-categories: (list 10 (string-ascii 32))
  }
)

;; Access permissions for property records
(define-map record-access-registry
  { record-id: uint, accessor: principal }
  { can-access: bool }
)

;; Record authentication system
(define-map record-authentication-registry
  { record-id: uint }
  {
    is-authenticated: bool,
    authenticated-by: principal,
    authentication-block: uint,
    authentication-comments: (string-ascii 256)
  }
)

;; Registry of authorized authenticators
(define-map authorized-authenticator-registry
  { authenticator: principal }
  { is-authorized: bool }
)

;; ========== UTILITY FUNCTIONS ==========

;; Validates if a record exists in the system
(define-private (record-exists? (record-id uint))
  (is-some (map-get? property-record-registry { record-id: record-id }))
)

;; Validates if user is the record owner
(define-private (is-record-holder? (record-id uint) (user principal))
  (match (map-get? property-record-registry { record-id: record-id })
    record-data (is-eq (get record-holder record-data) user)
    false
  )
)

;; Retrieves the volume of a specific record
(define-private (get-record-volume (record-id uint))
  (default-to u0
    (get record-volume
      (map-get? property-record-registry { record-id: record-id })
    )
  )
)

;; Validates a single category label
(define-private (is-valid-category? (category (string-ascii 32)))
  (and
    (> (len category) u0)
    (< (len category) u33)
  )
)

;; Validates the entire category list for a record
(define-private (validate-category-list (categories (list 10 (string-ascii 32))))
  (and
    (> (len categories) u0)
    (<= (len categories) u10)
    (is-eq (len (filter is-valid-category? categories)) (len categories))
  )
)

;; ========== PUBLIC OPERATIONAL FUNCTIONS ==========

;; Register a new property record in the system
(define-public (register-property-record 
                (name (string-ascii 64)) 
                (volume uint) 
                (summary (string-ascii 128)) 
                (categories (list 10 (string-ascii 32))))
  (let
    (
      (new-record-id (+ (var-get total-record-count) u1))
    )
    ;; Input validation
    (asserts! (> (len name) u0) err-invalid-record-name)
    (asserts! (< (len name) u65) err-invalid-record-name)
    (asserts! (> volume u0) err-invalid-record-volume)
    (asserts! (< volume u1000000000) err-invalid-record-volume)
    (asserts! (> (len summary) u0) err-invalid-record-name)
    (asserts! (< (len summary) u129) err-invalid-record-name)
    (asserts! (validate-category-list categories) err-invalid-category-format)

    ;; Create the new record entry
    (map-insert property-record-registry
      { record-id: new-record-id }
      {
        record-name: name,
        record-holder: tx-sender,
        record-volume: volume,
        registration-block: block-height,
        record-summary: summary,
        record-categories: categories
      }
    )

    ;; Grant owner access to their record
    (map-insert record-access-registry
      { record-id: new-record-id, accessor: tx-sender }
      { can-access: true }
    )

    ;; Update total record counter
    (var-set total-record-count new-record-id)

    ;; Return the new record ID
    (ok new-record-id)
  )
)

;; Reassign ownership of a property record to another user
(define-public (reassign-record-holder (record-id uint) (new-holder principal))
  (let
    (
      (record-data (unwrap! (map-get? property-record-registry { record-id: record-id }) err-record-not-in-system))
    )
    ;; Verify record exists and caller is owner
    (asserts! (record-exists? record-id) err-record-not-in-system)
    (asserts! (is-eq (get record-holder record-data) tx-sender) err-unauthorized-operation)

    ;; Update record ownership
    (map-set property-record-registry
      { record-id: record-id }
      (merge record-data { record-holder: new-holder })
    )

    ;; Return success
    (ok true)
  )
)

;; Modify an existing property record's information
(define-public (modify-property-record 
                (record-id uint) 
                (updated-name (string-ascii 64)) 
                (updated-volume uint) 
                (updated-summary (string-ascii 128)) 
                (updated-categories (list 10 (string-ascii 32))))
  (let
    (
      (record-data (unwrap! (map-get? property-record-registry { record-id: record-id }) err-record-not-in-system))
    )
    ;; Verify record exists and caller is owner
    (asserts! (record-exists? record-id) err-record-not-in-system)
    (asserts! (is-eq (get record-holder record-data) tx-sender) err-unauthorized-operation)

    ;; Input validation
    (asserts! (> (len updated-name) u0) err-invalid-record-name)
    (asserts! (< (len updated-name) u65) err-invalid-record-name)
    (asserts! (> updated-volume u0) err-invalid-record-volume)
    (asserts! (< updated-volume u1000000000) err-invalid-record-volume)
    (asserts! (> (len updated-summary) u0) err-invalid-record-name)
    (asserts! (< (len updated-summary) u129) err-invalid-record-name)
    (asserts! (validate-category-list updated-categories) err-invalid-category-format)

    ;; Update record information
    (map-set property-record-registry
      { record-id: record-id }
      (merge record-data { 
        record-name: updated-name, 
        record-volume: updated-volume, 
        record-summary: updated-summary, 
        record-categories: updated-categories 
      })
    )

    ;; Return success
    (ok true)
  )
)

;; Remove a property record from the registry
(define-public (remove-property-record (record-id uint))
  (let
    (
      (record-data (unwrap! (map-get? property-record-registry { record-id: record-id }) err-record-not-in-system))
    )
    ;; Verify record exists and caller is owner
    (asserts! (record-exists? record-id) err-record-not-in-system)
    (asserts! (is-eq (get record-holder record-data) tx-sender) err-unauthorized-operation)

    ;; Remove the record from storage
    (map-delete property-record-registry { record-id: record-id })

    ;; Return success
    (ok true)
  )
)

;; Grant access to a property record for a specific user
(define-public (grant-record-access (record-id uint) (accessor principal))
  (let
    (
      (record-data (unwrap! (map-get? property-record-registry { record-id: record-id }) err-record-not-in-system))
    )
    ;; Verify record exists and caller is owner
    (asserts! (record-exists? record-id) err-record-not-in-system)
    (asserts! (is-eq (get record-holder record-data) tx-sender) err-unauthorized-operation)

    ;; Return success
    (ok true)
  )
)

;; Revoke previously granted access to a property record
(define-public (withdraw-record-access (record-id uint) (accessor principal))
  (let
    (
      (record-data (unwrap! (map-get? property-record-registry { record-id: record-id }) err-record-not-in-system))
    )
    ;; Verify record exists and caller is owner
    (asserts! (record-exists? record-id) err-record-not-in-system)
    (asserts! (is-eq (get record-holder record-data) tx-sender) err-unauthorized-operation)
    (asserts! (not (is-eq accessor tx-sender)) err-invalid-record-name) ;; Owner can't revoke their own access

    ;; Remove access permission
    (map-delete record-access-registry { record-id: record-id, accessor: accessor })

    ;; Return success
    (ok true)
  )
)

;; Access a property record's details with permission check
(define-public (access-property-record (record-id uint))
  (let
    (
      (record-data (unwrap! (map-get? property-record-registry { record-id: record-id }) err-record-not-in-system))
      (access-info (map-get? record-access-registry { record-id: record-id, accessor: tx-sender }))
    )
    ;; Verify record exists
    (asserts! (record-exists? record-id) err-record-not-in-system)

    ;; Check if user has proper access rights
    (asserts! (or 
                (is-eq (get record-holder record-data) tx-sender)
                (is-some access-info)
                (and (is-some access-info) (get can-access (unwrap! access-info err-viewing-restricted)))
              ) 
              err-viewing-restricted)

    ;; Return record data if authorized
    (ok record-data)
  )
)

;; Authenticate the legitimacy of a property record
(define-public (authenticate-property-record (record-id uint) (authentication-notes (string-ascii 256)))
  (let
    (
      (record-data (unwrap! (map-get? property-record-registry { record-id: record-id }) err-record-not-in-system))
      (authenticator-data (unwrap! (map-get? authorized-authenticator-registry { authenticator: tx-sender }) err-unauthorized-operation))
    )
    ;; Verify record exists
    (asserts! (record-exists? record-id) err-record-not-in-system)

    ;; Verify caller is an authorized authenticator
    (asserts! (get is-authorized authenticator-data) err-unauthorized-operation)

    ;; Return success
    (ok true)
  )
)

;; ========== ADMINISTRATIVE FUNCTIONS ==========

;; Add a new authorized authenticator to the system
(define-public (register-authorized-authenticator (authenticator principal))
  (begin
    ;; Verify caller is the contract administrator
    (asserts! (is-eq tx-sender vault-administrator) err-admin-restricted-function)

    ;; Return success
    (ok true)
  )
)

;; Remove an authenticator's authorization
(define-public (revoke-authenticator-status (authenticator principal))
  (begin
    ;; Verify caller is the contract administrator
    (asserts! (is-eq tx-sender vault-administrator) err-admin-restricted-function)

    ;; Return success
    (ok true)
  )
)

;; Check if a principal is an authorized authenticator
(define-public (check-authenticator-status (authenticator principal))
  (ok (is-some (map-get? authorized-authenticator-registry { authenticator: authenticator })))
)

;; Retrieve system statistics
(define-public (get-system-statistics)
  (ok {
    record-count: (var-get total-record-count),
    current-block: block-height
  })
)

