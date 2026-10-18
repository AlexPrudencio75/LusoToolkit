using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace LusoToolkit
{
    // Window-scoped identity: never change the PowerShell process, registry,
    // shortcuts or other windows hosted by the same process.
    public static class TaskbarIdentity
    {
        public const string AppId = "AlexPrudencio.LusoToolkit";
        private static readonly PropertyKey IdentityKey = new PropertyKey(
            new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);

        [StructLayout(LayoutKind.Sequential)]
        private struct PropertyKey
        {
            public Guid Format;
            public uint Id;
            public PropertyKey(Guid format, uint id) { Format = format; Id = id; }
        }

        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore
        {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int GetAt(uint index, out PropertyKey key);
            [PreserveSig] int GetValue(ref PropertyKey key, IntPtr value);
            [PreserveSig] int SetValue(ref PropertyKey key, IntPtr value);
            [PreserveSig] int Commit();
        }

        [DllImport("shell32.dll", PreserveSig = true)]
        private static extern int SHGetPropertyStoreForWindow(
            IntPtr window, ref Guid iid, out IPropertyStore store);
        [DllImport("ole32.dll", PreserveSig = true)]
        private static extern int PropVariantClear(IntPtr value);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr window);
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        private static IPropertyStore Open(IntPtr window)
        {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            using (Process current = Process.GetCurrentProcess())
            {
                if (!IsWindow(window) || owner != (uint)current.Id)
                    throw new ArgumentException("Only a live window owned by this process is allowed.");
            }
            IPropertyStore store;
            Guid iid = typeof(IPropertyStore).GUID;
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(window, ref iid, out store));
            return store;
        }

        private static IntPtr EmptyVariant()
        {
            // PROPVARIANT is 16 bytes on x86, 24 on x64. Its string pointer
            // starts at offset 8 on both; allocating the native size avoids
            // struct packing/marshalling assumptions across PowerShell hosts.
            int size = IntPtr.Size == 8 ? 24 : 16;
            IntPtr value = Marshal.AllocCoTaskMem(size);
            for (int i = 0; i < size; i += 4) Marshal.WriteInt32(value, i, 0);
            return value;
        }

        private static void FreeVariant(IntPtr value)
        {
            PropVariantClear(value);
            Marshal.FreeCoTaskMem(value);
        }

        private static string Read(IPropertyStore store)
        {
            IntPtr value = EmptyVariant();
            try
            {
                PropertyKey key = IdentityKey;
                Marshal.ThrowExceptionForHR(store.GetValue(ref key, value));
                short kind = Marshal.ReadInt16(value);
                if (kind == 0) return null; // VT_EMPTY
                if (kind != 31) throw new InvalidOperationException("Unexpected AppUserModelID type.");
                return Marshal.PtrToStringUni(Marshal.ReadIntPtr(value, 8)); // VT_LPWSTR
            }
            finally { FreeVariant(value); }
        }

        public static string Get(IntPtr window)
        {
            IPropertyStore store = Open(window);
            try { return Read(store); }
            finally { Marshal.ReleaseComObject(store); }
        }

        private static void Write(IPropertyStore store, string identity)
        {
            IntPtr value = EmptyVariant();
            try
            {
                if (identity != null)
                {
                    IntPtr text = Marshal.StringToCoTaskMemUni(identity);
                    Marshal.WriteIntPtr(value, 8, text);
                    Marshal.WriteInt16(value, 31); // VT_LPWSTR; PropVariantClear owns text.
                }
                PropertyKey key = IdentityKey;
                // Window properties are committed immediately by SetValue.
                Marshal.ThrowExceptionForHR(store.SetValue(ref key, value));
            }
            finally { FreeVariant(value); }
        }

        public static void Apply(IntPtr window)
        {
            IPropertyStore store = Open(window);
            try { Write(store, AppId); }
            finally { Marshal.ReleaseComObject(store); }
        }

        public static void Clear(IntPtr window)
        {
            IPropertyStore store = Open(window);
            try
            {
                // Do not remove a property changed by somebody else.
                if (String.Equals(Read(store), AppId, StringComparison.Ordinal)) Write(store, null);
            }
            finally { Marshal.ReleaseComObject(store); }
        }
    }
}
