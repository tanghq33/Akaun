# 🧾 Akaun

A macOS app for tracking expenses, income, and claims.

## Overview

Akaun is a personal finance tracker built for freelancers, small business owners, and employees who need to manage expenses and submit reimbursement claims. It keeps a clear record of what you've spent, what you've earned, and what you're owed — all stored locally on your Mac, no account required.

## ✨ Features

- 📊 Dashboard with income vs. expense trend, profit summary, and category breakdown
- 🧾 Expense tracking with receipt attachments
- 💰 Income recording
- 📋 Claims management — group expenses together for reimbursement
- 🤖 Auto Import — drop a receipt or invoice and let AI fill in the details

## 📖 Sections

### 📊 Dashboard

Get a quick picture of your finances. The dashboard shows a 6-month income vs. expense trend chart, this month's profit, and a category breakdown so you can see where your money is going.

### 🧾 Expenses

Log each expense with the item name, supplier, date, amount (RM), category, and payment status (Unpaid or Paid). You can attach a supporting document such as a receipt or invoice. Each expense is automatically assigned a running number (e.g. `EX20260312-001`) for easy reference.

### 💰 Income

Record income with a date, amount, and an optional remark. Each entry gets an auto-assigned running number with the `IN` prefix.

### 📋 Claims

Group unpaid expenses into a claim when you need to submit them for reimbursement. Claims track their own status from Pending through to Done, and show the total amount across all included expenses.

### 🤖 Auto Import

Drop a receipt or invoice — image or PDF — and Akaun will scan it, send the text to an AI model, and pre-fill the expense details for you. Review the result and confirm to create the expense. This feature requires an OpenRouter API key (see setup below).

## 🔑 Auto Import Setup

To use Auto Import, you need a free [OpenRouter](https://openrouter.ai) account. Once you have an account:

1. Generate an API key from your OpenRouter dashboard.
2. Open Akaun and go to **Settings → Auto Import**.
3. Paste your API key and choose a model. Free models are available if you'd prefer not to spend credits.

## ⚙️ Settings

Settings has three panes:

- **Auto Import** — Enter your OpenRouter API key, pick a model, and set the token limit.
- **Categories** — Customise the list of expense categories to suit your business. The defaults cover common categories like Food & Beverage, Transport, and Office Supplies.
- **Reset** — Reset your expense data, app settings, or everything at once. Use with care.

## 🔒 Data & Privacy

All your data — expenses, income, claims, and settings — is stored locally on your Mac in the standard app support folder. Nothing is synced to the cloud. Attached documents are stored in `~/Library/Application Support/Akaun/Documents/`.

The only time data leaves your device is during Auto Import, when extracted receipt text is sent to the OpenRouter API to parse the details. No other information is transmitted.
