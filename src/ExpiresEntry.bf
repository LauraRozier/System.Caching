// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	[Ordered]
	struct ExpiresEntry
	{
		public _aUnion u;
		public int _cFree;
		public MemoryCacheEntry _cacheEntry;

		[Union]
		public struct _aUnion
		{
			public DateTime _utcExpires;
			public ExpiresEntryRef _next;
		}
	}

	struct ExpiresEntryRef
	{
		public static readonly ExpiresEntryRef INVALID = .(0, 0);

		private const uint ENTRY_MASK = 255U;
		private const uint PAGE_MASK = 4294967040U;
		private const int PAGE_SHIFT = 8;
		private uint _ref;

		public this(int pageIndex, int entryIndex)
		{
			_ref = (uint)(pageIndex << 8 | (entryIndex & 255));
		}

		public bool Equals(Object value) =>
			value is ExpiresEntryRef && _ref == ((ExpiresEntryRef)value)._ref;

		public static bool operator!=(ExpiresEntryRef r1, ExpiresEntryRef r2) =>
			r1._ref != r2._ref;

		public static bool operator==(ExpiresEntryRef r1, ExpiresEntryRef r2) =>
			r1._ref == r2._ref;

		public int GetHashCode() =>
			(int)_ref;

		public int PageIndex
		{
			get { return (int)(_ref >> 8); }
		}

		public int Index
		{
			get { return (int)(_ref & 255U); }
		}

		public bool IsInvalid
		{
			get { return _ref == 0U; }
		}
	}
}
