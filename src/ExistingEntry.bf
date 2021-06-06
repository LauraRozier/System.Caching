// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	public struct ExistingEntry
	{
		public EntryState State = .NotInCache;
		public Object Value = null;

		public this(EntryState state, Object value)
		{
			State = state;
			Value = value;
		}
	}
}
