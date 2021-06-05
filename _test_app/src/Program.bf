using System;
using System.Caching;
using System.Caching.Timer;
using System.Diagnostics;
using System.Threading;

namespace test_app
{
	class Program
	{
        const int CCacheTimeMilliseconds = 25000;
		
		static bool _running = true;
		static ConsoleCancelEventHandler _ctrlCHandler = new => CtrlCHandler;

		static int _cachedItem = 0;
        static readonly MemoryCache _memCache = MemoryCache.Default;
		static readonly CacheItemPolicy _policy = new .() {
			RemovedCallback = new => CacheItemPolicy_RemovedCallback
		} ~ delete _;

		static void Main()
		{
			CustomConsole.AddCancelKeyPressCallback(_ctrlCHandler);
			
			using (PeriodicCallback timer = scope .(new => DoStuff, TimeSpan(0, 0, 10)))
				while (_running)
					Thread.Sleep(100);
		}

		static void CtrlCHandler(Object sender, ConsoleCancelEventArgs e)
		{
			CustomConsole.WriteLine("Ctrl+C catched, exiting.");

			_running = false;
			e.Cancel = true;
		}

		static void DoStuff(PeriodicCallback caller)
		{
			_policy.AbsoluteExpiration = DateTimeOffset.Now.AddMilliseconds(CCacheTimeMilliseconds);
			CustomConsole.WriteLine(scope $"_cachedItem is now {_cachedItem}");

            // Only add if it is not there already (swallow others)
            ExistingEntry item = _memCache.AddOrGetExisting("Timer Update", new CallbackData(_cachedItem, Stopwatch.StartNew()), _policy, true);

			if (item.State == .RemovingFromCache || item.State == .RemovedFromCache)
				DeleteAndNullify!(item.Value);

			_cachedItem++;
		}

		static void CacheItemPolicy_RemovedCallback(CacheEntryRemovedArguments args)
		{
			CallbackData cd = (CallbackData)args.CacheItem.Value;
			cd.Stopwatch.Stop();

			if (_running)
				CustomConsole.WriteLine(scope $"\nItem is removed from the cache\n  Reason: {args.RemovedReason}\n  Item#: {cd.CahedItem}\n  Time spent in cache: {cd.Stopwatch.Elapsed}\n");

			DeleteAndNullify!(cd);
		}
	}

	class CallbackData
	{
		public int CahedItem;
		public Stopwatch Stopwatch ~ delete _;

		private this() {} // Hide default ctor

		public this(int aCahedItem, Stopwatch aStopwatch)
		{
			CahedItem = aCahedItem;
			Stopwatch = aStopwatch;
		}
	}

	/// Specifies combinations of modifier and console keys that can interrupt the current process.
	enum ConsoleSpecialKey
	{
		/// The Control modifier key plus the C console key.
		ControlC,
		/// The Control modifier key plus the BREAK console key.
		ControlBreak
	}

	sealed class ConsoleCancelEventArgs : EventArgs
	{
		private ConsoleSpecialKey _type;
		private bool _cancel;

		private this() {}

		public this(ConsoleSpecialKey type)
		{
			_type = type;
			_cancel = false;
		}

		/// Gets or sets a value that indicates whether simultaneously pressing the Control modifier key and the C console key (Ctrl+C) or the Ctrl+Break keys terminates the current process.
		/// The default is false, which terminates the current process.
		public bool Cancel
		{
			get { return _cancel; }
			set { _cancel = value; }
		}

		public ConsoleSpecialKey SpecialKey
		{
			get { return _type; }
		}
	}

	delegate void ConsoleCancelEventHandler(Object sender, ConsoleCancelEventArgs e);

	static class CustomConsole : Console
	{
		static Event<ConsoleCancelEventHandler> _cancelKeyPress ~ _.Dispose();

		public static void AddCancelKeyPressCallback(ConsoleCancelEventHandler handler)
		{
			_cancelKeyPress.Add(handler);
			
#if BF_PLATFORM_WINDOWS
			if (!WindowsConsole.CtrlHandlerAdded)
				WindowsConsole.AddCtrlHandler();
#endif
		}

		public static void RemoveCancelKeyPressCallback(ConsoleCancelEventHandler handler)
		{
			_cancelKeyPress.Remove(handler);
			
#if BF_PLATFORM_WINDOWS
			if (_cancelKeyPress.Count == 0 && WindowsConsole.CtrlHandlerAdded)
				WindowsConsole.RemoveCtrlHandler();
#endif
		}

		static void DoConsoleCancelEvent()
		{
			bool exitRequested = true;

			if (_cancelKeyPress.Count > 0)
			{
				ConsoleCancelEventArgs consoleCancelEventArgs = scope .(.ControlC);
				_cancelKeyPress(null, consoleCancelEventArgs);
				exitRequested = !consoleCancelEventArgs.Cancel;
			}

			if (exitRequested)
				Environment.Exit(58);
		}
		
#if BF_PLATFORM_WINDOWS
		static class WindowsConsole
		{
			// Delegate results in an AVE being thrown
			function bool WindowsCancelHandler(int keyCode);

			static WindowsCancelHandler cancelHandler = => DoWindowsConsoleCancelEvent;
			public static bool CtrlHandlerAdded = false;

			public static void AddCtrlHandler()
			{
				SetConsoleCtrlHandler(cancelHandler, true);
				CtrlHandlerAdded = true;
			}

			public static void RemoveCtrlHandler()
			{
				SetConsoleCtrlHandler(cancelHandler, false);
				CtrlHandlerAdded = false;
			}

			static bool DoWindowsConsoleCancelEvent(int keyCode)
			{
				if (keyCode == 0)
					CustomConsole.DoConsoleCancelEvent();

				return keyCode == 0;
			}

			[CLink, CallingConvention(.Stdcall)]
			static extern bool SetConsoleCtrlHandler(WindowsCancelHandler handler, bool addHandler);
		}
#endif
	}
}
