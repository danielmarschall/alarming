unit AudioVolCntrl;

interface

uses
  Windows, SysUtils;

procedure MuteAllAudioDevices(bMute: boolean);

implementation

uses
  ActiveX, ComObj;

type
  // https://stackoverflow.com/questions/49310147/iaudioendpointvolume-setmode-fails-with-a-call-to-an-os-function-failed
  BOOL = Cardinal;

const
  CLSID_MMDeviceEnumerator : TGUID = '{BCDE0395-E52F-467C-8E3D-C4579291692E}';
  IID_IMMDeviceEnumerator : TGUID = '{A95664D2-9614-4F35-A746-DE8DB63617E6}';
  IID_IMMDevice : TGUID = '{D666063F-1587-4E43-81F1-B948E807363F}';
  IID_IMMDeviceCollection : TGUID = '{0BD7A1BE-7A1A-44DB-8397-CC5392387B5E}';
  IID_IAudioEndpointVolume : TGUID = '{5CDF2C82-841E-4546-9722-0CF74078229A}';
  IID_IAudioMeterInformation : TGUID = '{C02216F6-8C67-4B5B-9D00-D008E73E0064}';
  IID_IAudioEndpointVolumeCallback : TGUID = '{657804FA-D6AD-4496-8A60-352752AF4F89}';
  IID_IMMNotificationClient : TGUID = '{7991EEC9-7E89-4D85-8390-6C703CEC60C0}';

  DEVICE_STATE_ACTIVE = $00000001;
  DEVICE_STATE_UNPLUGGED = $00000002;
  DEVICE_STATE_NOTPRESENT = $00000004;
  DEVICE_STATEMASK_ALL = $00000007;

type
  EDataFlow = TOleEnum;

const
  eRender = $00000000;
  eCapture = $00000001;
  eAll = $00000002;
  EDataFlow_enum_count = $00000003;

type
  ERole = TOleEnum;

const
  eConsole = $00000000;
  eMultimedia = $00000001;
  eCommunications = $00000002;
  ERole_enum_count = $00000003;

type
  IAudioEndpointVolumeCallback = interface(IUnknown)
  ['{657804FA-D6AD-4496-8A60-352752AF4F89}']
  end;

  IAudioEndpointVolume = interface(IUnknown)
  ['{5CDF2C82-841E-4546-9722-0CF74078229A}']
    function RegisterControlChangeNotify(AudioEndPtVol: IAudioEndpointVolumeCallback): HRESULT; stdcall;
    function UnregisterControlChangeNotify(AudioEndPtVol: IAudioEndpointVolumeCallback): HRESULT; stdcall;
    function GetChannelCount(out PInteger): HRESULT; stdcall;
    function SetMasterVolumeLevel(fLevelDB: single; pguidEventContext: PGUID): HRESULT; stdcall;
    function SetMasterVolumeLevelScalar(fLevelDB: single; pguidEventContext: PGUID): HRESULT; stdcall;
    function GetMasterVolumeLevel(out fLevelDB: single): HRESULT; stdcall;
    function GetMasterVolumeLevelScaler(out fLevelDB: single): HRESULT; stdcall;
    function SetChannelVolumeLevel(nChannel: Integer; fLevelDB: Single; pguidEventContext: PGUID): HRESULT; stdcall;
    function SetChannelVolumeLevelScalar(nChannel: Integer; fLevelDB: Single; pguidEventContext: PGUID): HRESULT; stdcall;
    function GetChannelVolumeLevel(nChannel: Integer; out fLevelDB: Single): HRESULT; stdcall;
    function GetChannelVolumeLevelScalar(nChannel: Integer; out fLevel: Single): HRESULT; stdcall;
    function SetMute(bMute: Boolean(*!*); pguidEventContext: PGUID): HRESULT; stdcall;
    function GetMute(out bMute: Boolean(*!*)): HRESULT; stdcall;
    function GetVolumeStepInfo(pnStep: Integer; out pnStepCount: Integer): HRESULT; stdcall;
    function VolumeStepUp(pguidEventContext: PGUID): HRESULT; stdcall;
    function VolumeStepDown(pguidEventContext: PGUID): HRESULT; stdcall;
    function QueryHardwareSupport(out pdwHardwareSupportMask): HRESULT; stdcall;
    function GetVolumeRange(out pflVolumeMindB: Single; out pflVolumeMaxdB: Single; out pflVolumeIncrementdB: Single): HRESULT; stdcall;
  end;

  IAudioMeterInformation = interface(IUnknown)
  ['{C02216F6-8C67-4B5B-9D00-D008E73E0064}']
    function GetPeakValue(out Peak: Real): HRESULT; stdcall;
  end;

  IPropertyStore = interface(IUnknown)
  end;

  IMMDevice = interface(IUnknown)
  ['{D666063F-1587-4E43-81F1-B948E807363F}']
    function Activate(const refId: TGUID; dwClsCtx: DWORD; pActivationParams: PInteger; out pEndpointVolume: IAudioEndpointVolume): HRESULT; stdCall;
    function OpenPropertyStore(stgmAccess: DWORD; out ppProperties: IPropertyStore): HRESULT; stdcall;
    function GetId(out ppstrId: PLPWSTR): HRESULT; stdcall;
    function GetState(out State: Integer): HRESULT; stdcall;
  end;

  IMMDeviceCollection = interface(IUnknown)
  ['{0BD7A1BE-7A1A-44DB-8397-CC5392387B5E}']
    function GetCount(out pcDevices: UINT): HRESULT; stdcall;
    function Item(nDevice: UINT; out ppDevice: IMMDevice): HRESULT; stdcall;
  end;

  IMMNotificationClient = interface(IUnknown)
  ['{7991EEC9-7E89-4D85-8390-6C703CEC60C0}']
  end;

  IMMDeviceEnumerator = interface(IUnknown)
  ['{A95664D2-9614-4F35-A746-DE8DB63617E6}']
    function EnumAudioEndpoints(dataFlow: EDataFlow; deviceState: SYSUINT; out DevCollection: IMMDeviceCollection): HRESULT; stdcall;
    function GetDefaultAudioEndpoint(EDF: SYSUINT; ER: SYSUINT; out Dev: IMMDevice): HRESULT; stdcall;
    function GetDevice(pwstrId: pointer; out Dev: IMMDevice): HRESULT; stdcall;
    function RegisterEndpointNotificationCallback(pClient: IMMNotificationClient): HRESULT; stdcall;
    function UnregisterEndpointNotificationCallback(pClient: IMMNotificationClient): HRESULT; stdcall;
  end;

procedure MuteAllAudioDevices(bMute: boolean);
var
  MMDeviceCollection: IMMDeviceCollection;
  MMDeviceEnumerator: IMMDeviceEnumerator;
  nDevCount: UINT;
  dev: IMMdevice;
  pEndpointVolume: IAudioEndpointVolume;
  iDev: Integer;
begin
  MMDeviceEnumerator := nil;
  OleCheck(CoCreateInstance(CLSID_MMDeviceEnumerator, nil, CLSCTX_ALL, IID_IMMDeviceEnumerator, MMDeviceEnumerator));

  MMDeviceCollection := nil;
  OleCheck(MMDeviceEnumerator.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, MMDeviceCollection));

  OleCheck(MMDeviceCollection.GetCount(nDevCount));

  for iDev := 0 to nDevCount - 1 do
  begin
    OleCheck(MMDeviceCollection.item(iDev, dev));
    OleCheck(Dev.Activate(IID_IAudioEndpointVolume, CLSCTX_INPROC_SERVER, nil, pEndpointVolume));
    OleCheck(pEndpointVolume.SetMute(bMute, nil));
  end;
end;

end.
