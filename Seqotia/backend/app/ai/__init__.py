"""AI adapters used by the local workspace."""

from .provider import (
    DemoSuggestionProvider,
    OpenAISuggestionProvider,
    SuggestionProvider,
    SuggestionProviderError,
    create_suggestion_provider,
)

__all__ = [
    "DemoSuggestionProvider",
    "OpenAISuggestionProvider",
    "SuggestionProvider",
    "SuggestionProviderError",
    "create_suggestion_provider",
]
