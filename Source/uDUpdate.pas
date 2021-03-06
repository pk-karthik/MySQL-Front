unit uDUpdate;

interface {********************************************************************}

uses
  Windows, Messages, Classes, Controls, SysUtils,
  Dialogs, StdCtrls, ComCtrls, Forms,
  Forms_Ext, StdCtrls_Ext,
  uDeveloper,
  uBase;

const
  UM_PAD_FILE_RECEIVED = WM_USER + 200;
  UM_SETUP_FILE_RECEIVED = WM_USER + 202;
  UM_UPDATE_PROGRESSBAR = WM_USER + 203;

type
  TDUpdate = class(TForm_Ext)
    FBCancel: TButton;
    FBForward: TButton;
    FProgram: TLabel;
    FProgressBar: TProgressBar;
    FVersionInfo: TLabel;
    GroupBox: TGroupBox_Ext;
    procedure FBCancelClick(Sender: TObject);
    procedure FBForwardClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormHide(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    SetupProgramStream: TFileStream;
    SetupProgramURI: string;
    FullHeight: Integer;
    HTTPThread: THTTPThread;
    PADFileStream: TStringStream;
    SetupPrgFilename: TFileName;
    procedure Progress(Sender: TObject; const Done, Size: Int64);
    procedure UMChangePreferences(var Message: TMessage); message UM_CHANGEPREFERENCES;
    procedure UMPADFileReceived(var Message: TMessage); message UM_PAD_FILE_RECEIVED;
    procedure UMSetupFileReceived(var Message: TMessage); message UM_SETUP_FILE_RECEIVED;
    procedure UMUpdateProgressBar(var Message: TMessage); message UM_UPDATE_PROGRESSBAR;
  public
    function Execute(): Boolean;
  end;

function DUpdate(): TDUpdate;

implementation {***************************************************************}

{$R *.dfm}

uses
  StrUtils,
  uPreferences;

var
  FDUpdate: TDUpdate;

function DUpdate(): TDUpdate;
begin
  if (not Assigned(FDUpdate)) then
  begin
    Application.CreateForm(TDUpdate, FDUpdate);
    FDUpdate.Perform(UM_CHANGEPREFERENCES, 0, 0);
  end;

  Result := FDUpdate;
end;

{ TDUpdate *************************************************************}

function TDUpdate.Execute(): Boolean;
begin
  Result := ShowModal() = mrOk;
end;

procedure TDUpdate.FBCancelClick(Sender: TObject);
begin
  if (Assigned(HTTPThread)) then
    HTTPThread.Terminate();
end;

procedure TDUpdate.FBForwardClick(Sender: TObject);
var
  Ext: string;
  FilenameP: array [0 .. MAX_PATH] of Char;
  I: Integer;
begin
  if (GetTempPath(MAX_PATH, FilenameP) > 0) then
  begin
    SetupPrgFilename := SetupProgramURI;
    while (Pos('/', SetupPrgFilename) > 0) do Delete(SetupPrgFilename, 1, Pos('/', SetupPrgFilename));

    if (not FileExists(FilenameP + SetupPrgFilename)) then
      SetupPrgFilename := FilenameP + SetupPrgFilename
    else
    begin
      Ext := ExtractFileExt(SetupPrgFilename);
      Delete(SetupPrgFilename, Length(SetupPrgFilename) - Length(Ext) + 1, Length(Ext));
      I := 2;
      while (FileExists(FilenameP + SetupPrgFilename + ' (' + IntToStr(I) + ')' + Ext)) do Inc(I);
      SetupPrgFilename := FilenameP + SetupPrgFilename + ' (' + IntToStr(I) + ')' + Ext;
    end;

    FProgram.Caption := Preferences.LoadStr(665) + ' ...';
    FProgram.Enabled := True;
    FBForward.Enabled := False;
    ActiveControl := FBCancel;

    SetupProgramStream := TFileStream.Create(SetupPrgFilename, fmCreate);

    HTTPThread := THTTPThread.Create(SetupProgramURI, nil, SetupProgramStream);
    HTTPThread.OnProgress := Progress;

    SendMessage(Handle, UM_UPDATE_PROGRESSBAR, 2, 100);

    HTTPThread.Start();
  end;
end;

procedure TDUpdate.FormCreate(Sender: TObject);
begin
  FullHeight := Height;
  HTTPThread := nil;
end;

procedure TDUpdate.FormDestroy(Sender: TObject);
begin
  if (Assigned(HTTPThread)) then
    TerminateThread(HTTPThread.Handle, 0);
end;

procedure TDUpdate.FormHide(Sender: TObject);
begin
  if (Assigned(PADFileStream)) then
    FreeAndNil(PADFileStream);
  if (Assigned(SetupProgramStream)) then
    FreeAndNil(SetupProgramStream);
end;

procedure TDUpdate.FormShow(Sender: TObject);
begin
  FVersionInfo.Caption := Preferences.LoadStr(663);
  FVersionInfo.Enabled := False;

  FProgram.Caption := Preferences.LoadStr(665);
  FProgram.Enabled := False;

  PADFileStream := TStringStream.Create();
  SetupProgramStream := nil;

  FVersionInfo.Caption := Preferences.LoadStr(663) + ' ...';
  FVersionInfo.Enabled := True;

  if (Assigned(HTTPThread)) then
    TerminateThread(HTTPThread.Handle, 0);
  HTTPThread := THTTPThread.Create(SysUtils.LoadStr(1005), nil, PADFileStream);
  HTTPThread.OnProgress := Progress;

  SendMessage(Handle, UM_UPDATE_PROGRESSBAR, 10, 100);

  HTTPThread.Start();

  FBForward.Enabled := False;
end;

procedure TDUpdate.Progress(Sender: TObject; const Done, Size: Int64);
begin
  PostMessage(Handle, UM_UPDATE_PROGRESSBAR, Done, Size);

  if (Done = Size) then
    if (Assigned(PADFileStream)) then
      PostMessage(Handle, UM_PAD_FILE_RECEIVED, 0, 0)
    else if (Assigned(SetupProgramStream)) then
      PostMessage(Handle, UM_SETUP_FILE_RECEIVED, 0, 0)
end;

procedure TDUpdate.UMChangePreferences(var Message: TMessage);
begin
  Caption := ReplaceStr(Preferences.LoadStr(666), '&', '');

  GroupBox.Caption := ReplaceStr(Preferences.LoadStr(224), '&', '');

  FBForward.Caption := Preferences.LoadStr(230);
  FBCancel.Caption := Preferences.LoadStr(30);
end;

procedure TDUpdate.UMPADFileReceived(var Message: TMessage);
var
  VersionStr: string;
begin
  HTTPThread.WaitFor();
  FreeAndNil(HTTPThread);

  Preferences.UpdateChecked := Now();

  if (not CheckOnlineVersion(PADFileStream, VersionStr, SetupProgramURI)) then
  begin
    FVersionInfo.Caption := Preferences.LoadStr(663) + ': ' + Preferences.LoadStr(384);
    MsgBox(Preferences.LoadStr(508), Preferences.LoadStr(45), MB_OK + MB_ICONERROR);
    FBCancel.Click();
  end
  else
  begin
    FVersionInfo.Caption := Preferences.LoadStr(663) + ': ' + VersionStr;

    if (OnlineProgramVersion <= Preferences.Version) then
    begin
      MsgBox(Preferences.LoadStr(507), Preferences.LoadStr(43), MB_OK + MB_ICONINFORMATION);
      FBCancel.Click();
    end
    else
    begin
      SendMessage(Handle, UM_UPDATE_PROGRESSBAR, 0, 0);

      FBForward.Enabled := True;
      ActiveControl := FBForward;
    end;
  end;
  FreeAndNil(PADFileStream);
end;

procedure TDUpdate.UMSetupFileReceived(var Message: TMessage);
begin
  HTTPThread.WaitFor();
  FreeAndNil(HTTPThread);

  FProgram.Caption := Preferences.LoadStr(665) + ': ' + Preferences.LoadStr(138);

  FreeAndNil(SetupProgramStream);

  Preferences.SetupProgram := SetupPrgFilename;
  Preferences.SetupProgramInstalled := False;

  ModalResult := mrOk;
end;

procedure TDUpdate.UMUpdateProgressBar(var Message: TMessage);
begin
  if (Message.LParam <= 0) then
  begin
    FProgressBar.Position := 0;
    FProgressBar.Max := 0;
  end
  else
  begin
    FProgressBar.Position := Integer(Message.WParam * 100) div Integer(Message.LParam);
    FProgressBar.Max := 100;
  end;
end;

initialization
  OnlineProgramVersion := -1;
  OnlineRecommendedVersion := -1;
  FDUpdate := nil;
end.
