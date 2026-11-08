Add-Type -AssemblyName System.Windows.Forms
$log = "$env:USERPROFILE\t_gl_log.txt"
function L($m){ "{0:HH:mm:ss.fff}  {1}" -f (Get-Date), $m | Out-File $log -Append -Encoding utf8 }
Add-Type -Path "$env:USERPROFILE\GetGL.cs"
L "старт"
$f = New-Object System.Windows.Forms.Form
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(-3000,-3000)
$f.Show(); [System.Windows.Forms.Application]::DoEvents()
$dc = [U6.G5]::GetDC($f.Handle); L "GetDC ок"
$pfd = New-Object U6.G5+PIXELFORMATDESCRIPTOR
$pfd.nSize = [uint16]40; $pfd.nVersion = 1
$pfd.dwFlags = [uint32]0x25; $pfd.iPixelType = 1; $pfd.cColorBits = 24; $pfd.cDepthBits = 24
$max = [U6.G5]::DescribePixelFormat($dc, 1, 40, [ref]$pfd)
L "всего форматов: $max"
$pf = [U6.G5]::ChoosePixelFormat($dc, [ref]$pfd)
L "ChoosePixelFormat = $pf"
[void][U6.G5]::DescribePixelFormat($dc, $pf, 40, [ref]$pfd)
$flags = [uint32]$pfd.dwFlags
L ("флаги формата {0}: 0x{1:X}  generic={2}  accel={3}" -f $pf, $flags, [bool]($flags -band 0x40), [bool]($flags -band 0x1000))
[void][U6.G5]::SetPixelFormat($dc, $pf, [ref]$pfd)
$ctx = [U6.G5]::wglCreateContext($dc)
if ($ctx -eq [IntPtr]::Zero) {
  L "wglCreateContext = NULL, err = $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
} else { L "wglCreateContext ок" }
$ok = [U6.G5]::wglMakeCurrent($dc, $ctx)
if (-not $ok) {
  L "wglMakeCurrent = false, err = $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
} else { L "wglMakeCurrent ок" }

# дамп собственных модулей прямо сейчас, пока контекст жив
try {
  $me = Get-Process -Id $PID
  $me.Modules | Where-Object {
    $_.FileName -match 'opengl32|atio6axx|atioglxx|atig6pxx|nvoglv|nvoglc|amdogl|aticfx'
  } | ForEach-Object { L "модуль: $($_.FileName)" }
} catch { L "дамп модулей не удался: $_" }

foreach ($n in 0x1F00, 0x1F01, 0x1F02) {
  $p = [U6.G5]::glGetString([uint32]$n)
  $s = if ($p -eq [IntPtr]::Zero) { "NULL" } else { [Runtime.InteropServices.Marshal]::PtrToStringAnsi($p) }
  L "GL: $s"
}
L "конец"
