"""Krum bounded contexts.

Each package owns one business capability.  Cross-context coupling is limited
to explicit service calls and foreign-key identifiers, never request objects.
"""
