// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Collections;

namespace System.Caching
{
	public abstract class CacheEntryChangeMonitor : ChangeMonitor
	{
		public abstract List<String> CacheKeys { get; }
		public abstract DateTimeOffset LastModified { get; }
	}
}
