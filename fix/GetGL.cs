using System;
using System.Runtime.InteropServices;
namespace U6 {
  public class G5 {
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("gdi32.dll", SetLastError=true)] public static extern int ChoosePixelFormat(IntPtr dc, ref PIXELFORMATDESCRIPTOR pfd);
    [DllImport("gdi32.dll", SetLastError=true)] public static extern bool SetPixelFormat(IntPtr dc, int pf, ref PIXELFORMATDESCRIPTOR pfd);
    [DllImport("gdi32.dll", SetLastError=true)] public static extern int DescribePixelFormat(IntPtr dc, int pf, uint size, ref PIXELFORMATDESCRIPTOR pfd);
    [DllImport("opengl32.dll", SetLastError=true)] public static extern IntPtr wglCreateContext(IntPtr dc);
    [DllImport("opengl32.dll", SetLastError=true)] public static extern bool wglMakeCurrent(IntPtr dc, IntPtr ctx);
    [DllImport("opengl32.dll")] public static extern IntPtr glGetString(uint name);
    [StructLayout(LayoutKind.Sequential)] public struct PIXELFORMATDESCRIPTOR {
      public ushort nSize; public ushort nVersion; public uint dwFlags; public byte iPixelType;
      public byte cColorBits; public byte cRedBits; public byte cRedShift;
      public byte cGreenBits; public byte cGreenShift; public byte cBlueBits; public byte cBlueShift;
      public byte cAlphaBits; public byte cAlphaShift; public byte cAccumBits;
      public byte cAccumRedBits; public byte cAccumGreenBits; public byte cAccumBlueBits; public byte cAccumAlphaBits;
      public byte cDepthBits; public byte cStencilBits; public byte cAuxBuffers;
      public byte iLayerType; public byte bReserved; public uint dwLayerMask;
      public uint dwVisibleMask; public uint dwDamageMask;
    }
  }
}
