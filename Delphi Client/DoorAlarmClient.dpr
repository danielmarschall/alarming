program DoorAlarmClient;

uses
  Forms,
  Windows,
  SysUtils,
  DoorAlarmClientMain in 'DoorAlarmClientMain.pas' {Form1},
  AudioVolCntrl in 'AudioVolCntrl.pas';

{$R *.res}

begin
  if CreateMutex(nil, True, '3E724D41-FB53-436B-A959-7B9236E55397') = 0 then
    RaiseLastOSError;
  if GetLastError = ERROR_ALREADY_EXISTS then
    Exit;

  Application.Initialize;
  Application.ShowMainForm := False;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
