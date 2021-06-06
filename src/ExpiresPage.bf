// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	struct ExpiresPage
	{
		public ExpiresEntry[] _entries;
		public int _pageNext;
		public int _pagePrev;
	}

	struct ExpiresPageList
	{
		public int _head;
		public int _tail;
	}
}
