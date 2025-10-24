# Flutter Ticket Sales App Blueprint

## 1. App Purpose

A Flutter mobile application that enables ticket sales agents to sell tickets and validate previously sold tickets through backend API integration.

### Core Functionality

*   Browse and search available tickets
*   Sell tickets to customers
*   Validate sold tickets (QR/barcode scanning)
*   View sales history and reports

---

## 2. Technical Architecture

### Technology Stack

*   **Frontend**: Flutter (Dart)
*   **State Management**: Provider
*   **HTTP Client**: `http` package
*   **Local Storage**: `shared_preferences` (for auth tokens) and `hive` (for offline caching)
*   **QR/Barcode Scanning**: `mobile_scanner`
*   **QR Generation**: `qr_flutter`

### Project Structure

```
lib/
├── main.dart
├── app/
│   ├── routes.dart
│   └── theme.dart
├── core/
│   ├── constants/
│   ├── utils/
│   └── widgets/
├── data/
│   ├── models/
│   ├── repositories/
│   └── services/
│       └── api_service.dart
├── features/
│   ├── auth/
│   ├── tickets/
│   ├── sales/
│   └── validation/
└── providers/
```

---

## 3. API Endpoints (Expected)

*   **Authentication**:
    *   `POST /api/auth/login`
    *   `POST /api/auth/refresh-token`
    *   `POST /api/auth/logout`
*   **Tickets**:
    *   `GET /api/tickets/available`
    *   `GET /api/tickets/{id}`
    *   `GET /api/tickets/categories`
*   **Sales**:
    *   `POST /api/sales/create`
    *   `GET /api/sales/history`
    *   `GET /api/sales/{id}`
*   **Validation**:
    *   `POST /api/validation/validate-ticket`
    *   `GET /api/validation/history`

---

## 4. User Stories

### Epic 1: Authentication & Account Management

*   **US-1.1: Agent Login**: As an agent, I want to log in with my credentials so that I can access the ticket sales system securely.
*   **US-1.2: Session Management**: As an agent, I want to stay logged in between app sessions so that I don't have to log in repeatedly.

### Epic 2: Browse & Search Tickets

*   **US-2.1: View Available Tickets**: As an agent, I want to see a list of all available tickets to inform customers about options.
*   **US-2.2: Search and Filter Tickets**: As an agent, I want to search and filter tickets by criteria to quickly find specific tickets.
*   **US-2.3: View Ticket Details**: As an agent, I want to view complete ticket information to answer customer questions.

### Epic 3: Ticket Sales

*   **US-3.1: Sell Single Ticket**: As an agent, I want to sell a ticket to a customer to complete the transaction.
*   **US-3.2: Sell Multiple Tickets**: As an agent, I want to sell multiple tickets in one transaction.
*   **US-3.3: View Sale Confirmation**: As an agent, I want to see immediate confirmation after a sale.
*   **US-3.4: Sales History**: As an agent, I want to view my past sales.

### Epic 4: Ticket Validation

*   **US-4.1: Scan Ticket QR Code**: As an agent, I want to scan a customer's ticket QR code to validate entry.
*   **US-4.2: View Validation Result**: As an agent, I want to see a clear validation status.
*   **US-4.3: Validation History**: As an agent, I want to view my validation history.

---

## 5. Data Models

*   **Ticket**
*   **Sale**
*   **Validation**

---

## 6. UI/UX Screens

*   Splash Screen
*   Login Screen
*   Home Dashboard
*   Tickets List
*   Ticket Details
*   Sell Ticket Screen
*   Sale Confirmation
*   Scanner Screen
*   Validation Result
*   Sales History
*   Profile/Settings

---

## 7. Development Plan

### Phase 1: Foundation (Current)

*   [x] Set up Flutter project structure based on the blueprint.
*   [ ] Implement navigation and routing.
*   [ ] Create API service layer with `http`.
*   [ ] Set up state management with `provider`.
*   [ ] Implement authentication (login, token storage, auto-login).
*   [ ] Create reusable UI components.
*   [ ] Set up error handling and logging.

---
