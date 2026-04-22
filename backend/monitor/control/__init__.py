"""Dashboard control plane — mutating endpoints under /control/*.

Every endpoint in this package requires the X-Monitor-Auth header to
match the MONITOR_CONTROL_TOKEN env var. See control.routes for wiring.
"""
