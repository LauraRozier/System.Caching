namespace System.Caching
{
	class NativeMethods
	{
		[CRepr]
		public struct MEMORYSTATUSEX
		{
			public int32 dwLength;
			public int32 dwMemoryLoad;
			public int64 ullTotalPhys;
			public int64 ullAvailPhys;
			public int64 ullTotalPageFile;
			public int64 ullAvailPageFile;
			public int64 ullTotalVirtual;
			public int64 ullAvailVirtual;
			public int64 ullAvailExtendedVirtual;

			public void Init() mut
			{
				dwLength = typeof(MEMORYSTATUSEX).Size;
			}
		}

		[CLink, CallingConvention(.Stdcall)]
		public extern static int GlobalMemoryStatusEx(MEMORYSTATUSEX* memoryStatusEx);
	}
}
