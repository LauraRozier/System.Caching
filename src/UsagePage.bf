// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	[Ordered]
	struct UsagePage
	{
		public UsageEntry[] Entries = null;
		public int NextPage;
		public int PreviousPage;
	}

	[Ordered]
	struct UsagePageList
	{
		public int Head;
		public int Tail;
	}
}
