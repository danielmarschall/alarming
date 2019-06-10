unit DoorAlarmClientMain;

// TODO: make configurable, which actions should be executed (e.g. run programs) when a motion was detected, with different event sounds etc
// TODO: ask server to subscribe/unsubscribe to events (doorbell, motion)

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, HTTPApp, StdCtrls,
  IdHTTPServer, idContext, idCustomHTTPServer, OleCtrls, SHDocVw, ExtCtrls,
  JPEG, MJPEGDecoderUnit, IniFiles, Menus;

type
  TAlarmType = (atUnknown, atMotion, atDoorbell);

  TForm1 = class(TForm)
    Image1: TImage;
    TrayIcon1: TTrayIcon;
    PopupMenu1: TPopupMenu;
    Exit1: TMenuItem;
    Open1: TMenuItem;
    Image2: TImage;
    CloseTimer: TTimer;
    UpdateIPTimer: TTimer;
    Allowmutingsoundinterface1: TMenuItem;
    N1: TMenuItem;
    Startalarm1: TMenuItem;
    N2: TMenuItem;
    Stopalarm1: TMenuItem;
    Gotocontrolpanelwebsite1: TMenuItem;
    doorbellPanel: TPanel;
    N3: TMenuItem;
    Ignoredoorbell1: TMenuItem;
    Ignoremotionalert1: TMenuItem;
    unknownAlarm: TPanel;
    procedure FormDestroy(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure TrayIcon1Click(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure Exit1Click(Sender: TObject);
    procedure Open1Click(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormHide(Sender: TObject);
    procedure CloseTimerTimer(Sender: TObject);
    procedure UpdateIPTimerTimer(Sender: TObject);
    procedure Startalarm1Click(Sender: TObject);
    procedure Stopalarm1Click(Sender: TObject);
    procedure Gotocontrolpanelwebsite1Click(Sender: TObject);
    procedure ImageClick(Sender: TObject);
  private
    MJPEGDecoder: TMJPEGDecoder;
    LastDingDong: TDateTime;
    SimpleCS: boolean;
    ini: TMemIniFile;
    last_known_webcam_port: integer;
    procedure ServerCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure MotionDetected;
    procedure HandleFrame(Sender: TObject; Frame: TJPEGImage);
    procedure WMQueryEndSession(var Message: TWMQueryEndSession); message WM_QUERYENDSESSION;
    procedure StartStream;
    procedure StopStream;
    procedure DoShowForm(AlarmType: TAlarmType);
    procedure DoPosition;
    procedure StopMusic;
    function ControlServerUrl: string;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  mmSystem, idhttp, DateUtils, ActiveX, ComObj, AudioVolCntrl, ShellAPI;

var
  Server: TIdHTTPServer;
  gShuttingDown: boolean;

procedure CallUrl(const url: string);
var
  idhttp: TIdHTTP;
begin
  if url <> '' then
  begin
    idhttp := TIdHTTP.Create(nil);
    try
      idhttp.Get(url);
    finally
      FreeAndNil(idhttp);
    end;
  end;
end;

procedure TForm1.Stopalarm1Click(Sender: TObject);
var
  lParamList: TStringList;
  idhttp: TIdHttp;
begin
  try
    try
      lParamList := TStringList.Create;
      lParamList.Add('action=motion_off'); // 1.3.6.1.4.1.37476.2.4.1.101

      idhttp := TIdHTTP.Create(nil);
      try
        idhttp.Post(ControlServerUrl, lParamList);
      finally
        FreeAndNil(idhttp);
      end;
    finally
      FreeAndNil(lParamList);
    end;
  except
    // Nothing
  end;
end;

procedure TForm1.StopMusic;
const
  TIMEOUT = 1000; // ms
var
  lpdwResult: DWORD;
begin
  // Stops Spotify, WMP, etc.
  lpdwResult := 0;
  SendMessageTimeout(HWND_BROADCAST, WM_APPCOMMAND, 0, MAKELONG(0, APPCOMMAND_MEDIA_STOP), SMTO_NORMAL, TIMEOUT, lpdwResult);

  // Mutes everything (also YouTube)
  if Allowmutingsoundinterface1.Checked then
  begin
    OleCheck(CoInitialize(nil));
    try
      MuteAllAudioDevices(true);
    finally
      CoUninitialize;
    end;
  end;
end;

procedure TForm1.HandleFrame(Sender: TObject; Frame: TJPEGImage);
begin
  try
    Image1.Picture.Bitmap.Assign(Frame);

    Left := Left + (ClientWidth  - Image1.Picture.Width);
    Top  := Top  + (ClientHeight - Image1.Picture.Height);

    ClientWidth := Image1.Picture.Width;
    ClientHeight := Image1.Picture.Height;
  finally
    Frame.Free;
  end;
end;

procedure TForm1.ImageClick(Sender: TObject);
(*
var
  pnt: TPoint;
*)
begin
  (*
  if GetCursorPos(pnt) then
    PopupMenu1.Popup(pnt.X, pnt.Y);
  *)
end;

procedure TForm1.WMQueryEndSession(var Message: TWMQueryEndSession);
begin
  gShuttingDown := true;
  Message.Result := 1;
end;

procedure TForm1.Startalarm1Click(Sender: TObject);
var
  lParamList: TStringList;
  idhttp: TIdHttp;
begin
  try
    try
      lParamList := TStringList.Create;
      lParamList.Add('action=motion_on'); // 1.3.6.1.4.1.37476.2.4.1.100

      idhttp := TIdHTTP.Create(nil);
      try
        idhttp.Post(ControlServerUrl, lParamList);
      finally
        FreeAndNil(idhttp);
      end;
    finally
      FreeAndNil(lParamList);
    end;
  except
    // Nothing
  end;
end;

procedure TForm1.StartStream;
begin
  if last_known_webcam_port = 0 then exit;

  MJPEGDecoder.OnFrame := HandleFrame;
  MJPEGDecoder.OnError := nil;
  MJPEGDecoder.OnMessage := nil;
  MJPEGDecoder.Connect(ini.ReadString('Server', 'Address', '127.0.0.1'),
                       last_known_webcam_port,
                       '/');
end;

procedure TForm1.StopStream;
begin
  MJPEGDecoder.Disconnect;
end;

procedure TForm1.CloseTimerTimer(Sender: TObject);
begin
  CloseTimer.Enabled := false;
  Close;
end;

procedure TForm1.MotionDetected;
var
  AlarmSound: string;
  DingDongMinInterval: integer;
begin
  DingDongMinInterval := ini.ReadInteger('Sound', 'AlarmMinInterval', 10);
  if SecondsBetween(Now, LastDingDong) > DingDongMinInterval then
  begin
    LastDingDong := Now;

    if ini.ReadBool('Sound', 'StopMusic', true) then
    begin
      StopMusic;
    end;

    AlarmSound := ini.ReadString('Sound', 'AlarmSoundFile', '');
    if AlarmSound <> '' then
    begin
      PlaySound(PChar(AlarmSound), 0, SND_ALIAS or SND_ASYNC);
    end;
  end;
end;

procedure TForm1.Exit1Click(Sender: TObject);
begin
  gShuttingDown := true;
  Close;
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CloseTimer.Enabled := false;
  CanClose := gShuttingDown;
  if not CanClose then Hide;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  ini := TMemIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));

  DoubleBuffered := true;

  Server := TIdHTTPServer.Create();
  Server.DefaultPort := ini.ReadInteger('Client', 'ListenPort', 80);
  Server.OnCommandGet := ServerCommandGet;
  Server.Active := true;

  Gotocontrolpanelwebsite1.Visible := true;
  Startalarm1.Visible := true;
  Stopalarm1.Visible := true;
  N2.Visible := Gotocontrolpanelwebsite1.Visible or Startalarm1.Visible or Stopalarm1.Visible;

  MJPEGDecoder := TMJPEGDecoder.Create(Self);

  DoPosition;

  // Question: Should these settings also be saved for the next program session?
  Allowmutingsoundinterface1.Checked := ini.ReadBool('Client', 'AllowMute', false);
  Ignoredoorbell1.Checked := ini.ReadBool('Client', 'IgnoreDoorbell', false);
  Ignoremotionalert1.Checked := ini.ReadBool('Client', 'IgnoreMotion', false);

  UpdateIPTimerTimer(UpdateIPTimer);
  UpdateIPTimer.Interval := ini.ReadInteger('Client', 'SubscribeInterval', 30*60) * 1000;
  UpdateIPTimer.Enabled := true;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(Server) then Server.Active := false;
  FreeAndNil(Server);

  FreeAndNil(ini);

  FreeAndNil(MJPEGDecoder);
end;

procedure TForm1.FormHide(Sender: TObject);
begin
  if Image2.Visible then
    StopStream;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if Image2.Visible then
    StartStream;
end;

procedure TForm1.Gotocontrolpanelwebsite1Click(Sender: TObject);
begin
  ShellExecute(Handle, 'open', PChar(ControlServerUrl), '', '', SW_NORMAL);
end;

procedure TForm1.Open1Click(Sender: TObject);
begin
  TrayIcon1Click(TrayIcon1);
end;

procedure TForm1.ServerCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  AutoCloseTimerInterval: integer;
  AlarmType: TAlarmType;
begin
  aResponseInfo.ResponseNo  := 200;
  aResponseInfo.ContentType := 'text/html';
  aResponseInfo.ContentText := '';

  if (ARequestInfo.CommandType = hcPOST) and
     (ARequestInfo.Params.Values['action'] = 'client_alert') then // 1.3.6.1.4.1.37476.2.4.1.3
  begin
    if ARequestInfo.Params.Values['motion_port'] <> '' then
    begin
      TryStrToInt(ARequestInfo.Params.Values['motion_port'], last_known_webcam_port);
    end;

    if ARequestInfo.Params.Values['simulation'] = '1' then
    begin
      exit;
    end;

    if SimpleCS then exit;
    SimpleCS := true;
    try
      if CloseTimer.Enabled then
      begin
        CloseTimer.Enabled := false;
        CloseTimer.Enabled := true; // "Restart" timer
      end;

      AutoCloseTimerInterval := ini.ReadInteger('Client', 'AutoCloseTimer', 5000);
      if (not Visible) and (AutoCloseTimerInterval <> -1) then
      begin
        CloseTimer.Interval := AutoCloseTimerInterval;
        CloseTimer.Enabled := true;
      end;

      if ARequestInfo.Params.IndexOf('targets=1.3.6.1.4.1.37476.2.4.2.1002' {camera, motion}) >= 0 then
        AlarmType := atMotion
      else if ARequestInfo.Params.IndexOf('targets=1.3.6.1.4.1.37476.2.4.2.2001' {sound, doorbell}) >= 0 then
        AlarmType := atDoorbell
      else
      begin
        // TODO: Make plugin DLLs ?
        AlarmType := atUnknown;
      end;

      // Attention: Ignoring these events at the client does not prevent the server
      // doing other actions (e.g. ask Spotify to stop the music on connected devices)
      if Ignoredoorbell1.Checked and (AlarmType = atDoorbell) then Exit;
      if Ignoremotionalert1.Checked and (AlarmType = atMotion) then Exit;

      if AlarmType = atUnknown then
      begin
        unknownAlarm.ShowHint := true;
        unknownAlarm.Hint := ARequestInfo.Params.Text;
      end;
      DoShowForm(AlarmType);

      if ini.ReadBool('Client', 'AutoPopup', true) then
      begin
        Application.Restore;
        WindowState := wsNormal;
      end;

      if ini.ReadBool('Client', 'AlarmStayOnTop', true) then
        FormStyle := fsStayOnTop
      else
        FormStyle := fsNormal;

      MotionDetected;
    finally
      SimpleCS := false;
    end;
  end;
end;

procedure TForm1.TrayIcon1Click(Sender: TObject);
begin
  // TODO: when clicked, the icon-selection won't close
  Application.Restore;
  WindowState := wsNormal;
  FormStyle := fsNormal;
  DoShowForm(atMotion);
end;

procedure TForm1.UpdateIPTimerTimer(Sender: TObject);
var
  lParamList: TStringList;
  idhttp: TIdHttp;
begin
  try
    try
      lParamList := TStringList.Create;
      lParamList.Add('action=client_subscribe'); // 1.3.6.1.4.1.37476.2.4.1.1
      lParamList.Add('port='+ini.ReadString('Client', 'ListenPort', ''));
      lParamList.Add('ttl='+IntToStr((UpdateIPTimer.Interval div 1000) * 2 + 10));
      lParamList.Add('targets=1.3.6.1.4.1.37476.2.4.2.0');    // Any
      lParamList.Add('targets=1.3.6.1.4.1.37476.2.4.2.1002'); // Motion, camera
      lParamList.Add('targets=1.3.6.1.4.1.37476.2.4.2.2001'); // Sound, doorbell

      idhttp := TIdHTTP.Create(nil);
      try
        idhttp.Post(ControlServerUrl, lParamList);
      finally
        FreeAndNil(idhttp);
      end;
    finally
      FreeAndNil(lParamList);
    end;
  except
    // Nothing
  end;
end;

function TForm1.ControlServerUrl: string;
begin
  result := 'http://' + ini.ReadString('Server', 'Address', '127.0.0.1') + ':' + ini.ReadString('Server', 'Port', '80') + '/';
end;

procedure TForm1.DoPosition;
  function _TaskBarHeight: integer;
  var
    hTB: HWND;
    TBRect: TRect;
  begin
    hTB := FindWindow('Shell_TrayWnd', '');
    if hTB = 0 then
      Result := 0
    else
    begin
      GetWindowRect(hTB, TBRect);
      Result := TBRect.Bottom - TBRect.Top;
    end;
  end;
begin
  // TODO: modify this code so that it works also if the task bar is on top or on the right corner of the screen
  // TODO: user should select in which corner the window show be
  Self.Left := Screen.Width - Self.Width;
  Self.Top := Screen.Height - Self.Height - _TaskBarHeight;
end;

procedure TForm1.DoShowForm(AlarmType: TAlarmType);
begin
  Image1.Visible := AlarmType = atMotion;
  Image2.Visible := AlarmType = atMotion;

  // BUGBUG! TODO: This does not work. The panels are not visible for some reason! I just get a white window!
  doorbellPanel.Visible := AlarmType = atDoorbell;
  unknownAlarm.Visible := AlarmType = atUnknown;

  if ini.ReadBool('Client', 'AutoReposition', true) then
  begin
    DoPosition;
  end;

  Show;
end;

end.
