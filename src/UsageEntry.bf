// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	[Ordered]
	struct UsageEntry
	{
		public UsageEntryLink _ref1;
		public int FreeCount;
		public UsageEntryLink _ref2;
		public DateTime UtcDate;
		public MemoryCacheEntry CacheEntry;
	}
	
	[Ordered]
	struct UsageEntryLink
	{
		public UsageEntryRef Next;
		public UsageEntryRef Previous;
	}

	struct UsageEntryRef
	{
		private const uint ENTRY_MASK = 255U;
		private const uint PAGE_MASK = 4294967040U;
		private const int PAGE_SHIFT = 8;

		public static readonly UsageEntryRef INVALID = UsageEntryRef(0, 0);

		private uint _ref;

		public this(int pageIndex, int entryIndex)
		{
			_ref = (uint)(pageIndex << 8 | (entryIndex & 255));
		}

		public bool Equals(Object value) =>
			value is UsageEntryRef && _ref == ((UsageEntryRef)value)._ref;

		public static bool operator==(UsageEntryRef r1, UsageEntryRef r2) =>
			r1._ref == r2._ref;

		public static bool operator!=(UsageEntryRef r1, UsageEntryRef r2) =>
			r1._ref != r2._ref;

		public int GetHashCode() =>
			(int)_ref;

		public int PageIndex
		{
			get { return (int)(_ref >> 8); }
		}

		public int Ref1Index
		{
			get { return (int)((int8)(_ref & 255U)); }
		}

		public int Ref2Index
		{
			get { return -(int)((int8)(_ref & 255U)); }
		}

		public bool IsRef1
		{
			get { return (int8)(_ref & 255U) > 0; }
		}

		public bool IsRef2
		{
			get { return (int8)(_ref & 255U) < 0; }
		}

		public bool IsInvalid
		{
			get { return _ref == 0U; }
		}
	}
}
