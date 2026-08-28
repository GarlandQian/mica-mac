# Backend Development Guidelines

This directory contains the active MicaCore/controller contract. Mica talks to
controllers that are already running and authorized by the user; it does not
own a local core or network configuration.

## Active Contract

| Guide | Description | Status |
|-------|-------------|--------|
| [Controller Data Contract](./controller-data-contract.md) | Ordered decoding, backend capability boundaries, optional fields, validation, cancellation, and privacy | Active |

Use the controller data contract whenever a controller response is decoded,
normalized, projected, persisted, or exposed to Workbench presentation. It is
the source for controller-reported order and optionality, typed capability
gates, endpoint validation, cancellation propagation, and export restrictions.

Backend-specific behavior belongs in the owning adapter or client. Keep
transport errors typed, preserve backend fields until presentation, and never
invent controller business data to fill an unavailable response.

**Language**: All documentation should be written in **English**.
