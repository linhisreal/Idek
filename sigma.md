# Plans

Plans for making handling each unique payment session to prevent sample session interaction with each others and might cause security issues

## Ideas

```mermaid
flowchart TD
    A[User starts payment] --> B{Payment type?}
    B -->|Robux| C[Show gamepass info]
    B -->|PayPal| D[Redirect to SellPass]
    B -->|Other methods| E[Show payment modal]
    
    E --> F[Collect payment details]
    F --> G[Create payment session]
    G --> H[Show upload proof instructs]
    
    %% User cancellation branch - happens earlier in the flow
    H -->|User cancels| O[Find session by sessionId]
    O --> V[Send cancellation confirmation]
    V --> W[Delete session]
    
    %% Normal continuation
    H -->|Continue| I[User uploads proof image]
    I --> J[Store proof URL in session]
    J --> K[Notify admins with sessionID]
    
    K --> L{Admin decision}
    L -->|Approve| M[Find session by sessionId]
    L -->|Reject| N[Find session by sessionId]
    
    M --> P[Assign license key]
    P --> Q[Update all admin messages]
    Q --> R[Delete session]
    
    N --> S[Send rejection notification]
    S --> T[Update all admin messages]
    T --> U[Delete session]
```

## V1 - PaymentSession

### Class

```mermaid
classDiagram
    class DiscordClient {
        Map(string, PaymentData) tempPaymentData
    }
    
    class PaymentData {
        string licenseType
        string paymentMethod
        string transactionId
        string contactInfo
        string notes
        number timestamp
        string imageProofUrl
        string channelId
        string statusMessageId
        Array adminMessages
    }

    DiscordClient "1" --o "*" PaymentData : stores
```

### Structure

```mermaid
sequenceDiagram
    participant User
    participant Bot as Discord Bot
    participant Map as tempPaymentData Map
    participant Admin as Admin User

    User->>Bot: Start payment process
    Bot->>Map: Store payment data with user ID as key
    Note over Map: Map<userId, paymentData>
    Bot->>User: Ask for payment proof

    User->>Bot: Upload payment proof
    Bot->>Map: Update with proof image URL
    Bot->>Admin: Send notification with approve/reject buttons

    alt Payment Approved
        Admin->>Bot: Click "Approve"
        Bot->>Map: Look up payment data by user ID
        Bot->>User: Send license key
        Bot->>Map: Remove payment data
    else Payment Rejected
        Admin->>Bot: Click "Reject"
        Bot->>Map: Look up payment data by user ID
        Bot->>User: Send rejection notification
        Bot->>Map: Remove payment data
    else User Cancels
        User->>Bot: Click "Cancel"
        Bot->>Map: Look up payment data by user ID
        Bot->>User: Send cancellation confirmation
        Bot->>Map: Remove payment data
    end
```

## V2 - PaymentSession

### Class

```mermaid
classDiagram
    class PaymentSessionManager {
        -Map(userId, Array(SessionObject)) sessions
        +createSession(userId, data) string
        +getSessionById(sessionId) object
        +getLatestSession(userId) object
        +updateSession(sessionId, data) boolean
        +deleteSession(sessionId) boolean
    }
    
    class SessionObject {
        string sessionId
        string userId
        string licenseType
        string paymentMethod
        string transactionId
        string contactInfo
        string notes
        number createdAt
        string imageProofUrl
        string statusMessageId
        string channelId
        Array adminMessages
    }

    PaymentSessionManager "1" --o "many" SessionObject : contains
```

### Structure

```mermaid
sequenceDiagram
    participant User
    participant Bot as Discord Bot
    participant PSM as PaymentSessionManager
    participant Admin as Admin User

    User->>Bot: Start payment process
    Bot->>PSM: createSession(userId, paymentData)
    Note over PSM: Generates unique sessionId = userId_timestamp
    PSM-->>Bot: Return sessionId
    Bot->>User: Ask for proof with buttons containing sessionId

    User->>Bot: Upload payment proof
    Bot->>PSM: getSessionById(sessionId)
    PSM-->>Bot: Return session data
    Bot->>PSM: updateSession(sessionId, {imageProofUrl, statusMessageId})
    Bot->>Admin: Send notification with approve/reject buttons containing sessionId

    alt Payment Approved
        Admin->>Bot: Click "Approve" with sessionId
        Bot->>PSM: getSessionById(sessionId)
        PSM-->>Bot: Return session data
        Bot->>User: Send license key
        Bot->>PSM: deleteSession(sessionId)
    else Payment Rejected
        Admin->>Bot: Click "Reject" with sessionId
        Bot->>PSM: getSessionById(sessionId)
        PSM-->>Bot: Return session data
        Bot->>User: Send rejection notification
        Bot->>PSM: deleteSession(sessionId)
    else User Cancels
        User->>Bot: Click "Cancel" with sessionId
        Bot->>PSM: getSessionById(sessionId)
        PSM-->>Bot: Return session data
        Bot->>User: Send cancellation confirmation
        Bot->>PSM: deleteSession(sessionId)
    end

    Note over PSM: Sessions are stored per user in arrays,<br/>allowing multiple concurrent sessions
```
