// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	public delegate void OnChangedCallback(Object state);

	public delegate void CacheEntryRemovedCallback(CacheEntryRemovedArguments arguments);

	public delegate void CacheEntryUpdateCallback(CacheEntryUpdateArguments arguments);

	public delegate void PeriodicCallbackDelegate(PeriodicCallback state);
}
