unit fTools;

interface {********************************************************************}

// ODBC Driver: http://www.microsoft.com/en-us/download/details.aspx?id=13255

uses
  Windows, XMLDoc, XMLIntf, DBGrids, msxml, Zip, WinSpool, Printers,
  SysUtils, DB, Classes, Graphics, SyncObjs,
  {$IFDEF EurekaLog}
  ExceptionLog,
  {$ENDIF}
  ODBCAPI,
  SynEditHighlighter,
  SynPDF,
  MySQLConsts, MySQLDB, SQLUtils, CSVUtils,
  fSession, fPreferences;

type
  TTool = class(TThread)
  type
    TItems = class;
    TItem = class
    private
      FItems: TItems;
      function GetIndex(): Integer; inline;
    protected
      property Items: TItems read FItems;
    public
      Done: Boolean;
      RecordsDone: Integer;
      RecordsSum: Int64;
      constructor Create(const AItems: TTool.TItems);
      property Index: Integer read GetIndex;
    end;
    TDBObjectItem = class(TItem)
    private
      FDBObject: TSDBObject;
    public
      constructor Create(const AItems: TTool.TItems; const ADBObject: TSDBObject);
      property DBObject: TSDBObject read FDBObject;
    end;
    TItems = class(TList)
    private
      FTool: TTool;
      function GetItem(Index: Integer): TItem; inline;
    public
      constructor Create(const ATool: TTool);
      destructor Destroy(); override;
      property Item[Index: Integer]: TItem read GetItem; default;
      property Tool: TTool read FTool;
    end;
    TErrorType = (TE_Database, TE_NoPrimaryIndex, TE_File, TE_ODBC, TE_XML, TE_Warning, TE_Printer);
    TError = record
      ErrorType: TErrorType;
      ErrorCode: Integer;
      ErrorMessage: string;
      Session: TSSession;
    end;
    TErrorEvent = procedure(const Sender: TObject; const Error: TError; const Item: TItem; const ShowRetry: Boolean; var Success: TDataAction) of object;
    TOnExecuted = procedure(const Success: Boolean) of object;
    PProgressInfos = ^TProgressInfos;
    TProgressInfos = record
      TablesDone, TablesSum: Integer;
      RecordsDone, RecordsSum: Int64;
      TimeDone, TimeSum: TDateTime;
      Progress: Byte;
    end;
    TOnUpdate = procedure(const ProgressInfos: TProgressInfos) of object;

    TDataFileBuffer = class
    private
      Buffer: record
        Mem: PAnsiChar;
        Size: Integer;
        Write: PAnsiChar;
      end;
      CodePage: Cardinal;
      MaxCharSize: Integer;
      Temp1: record
        Mem: Pointer;
        Size: Integer;
      end;
      Temp2: record
        Mem: Pointer;
        Size: Integer;
      end;
      function GetData(): Pointer; inline;
      function GetSize(): Integer; inline;
      procedure Resize(const NeededSize: Integer);
    public
      procedure Clear();
      constructor Create(const ACodePage: Cardinal);
      destructor Destroy(); override;
      procedure Write(const Data: Pointer; const Size: Integer; const Quote: Boolean = False); overload;
      procedure WriteData(const Text: PChar; const Length: Integer; const Quote: Boolean = False); overload;
      procedure WriteText(const Text: PChar; const Length: Integer); overload;
      procedure WriteText(const Text: my_char; const Length: Integer; const CodePage: Cardinal); overload;
      procedure WriteBinary(const Value: PChar; const Length: Integer); overload;
      procedure WriteBinary(const Value: my_char; const Length: Integer); overload;
      property Data: Pointer read GetData;
      property Size: Integer read GetSize;
    end;

    TStringBuffer = class
    private
      Buffer: record
        Mem: PChar;
        Size: Integer;
        Write: PChar;
      end;
      function GetData(): Pointer; inline;
      function GetSize(): Integer; inline;
      procedure Resize(const NeededLength: Integer);
    public
      procedure Clear(); virtual;
      constructor Create(const MemSize: Integer);
      destructor Destroy(); override;
      function Read(): string; virtual;
      procedure Write(const Text: string); overload; inline;
      property Data: Pointer read GetData;
      property Size: Integer read GetSize;
    end;

  private
    CriticalSection: TCriticalSection;
    FErrorCount: Integer;
    FItems: TItems;
    FOnError: TErrorEvent;
    FOnExecuted: TOnExecuted;
    FOnUpdate: TOnUpdate;
    FUserAbort: TEvent;
    ProgressInfos: TProgressInfos;
  protected
    StartTime: TDateTime;
    Success: TDataAction;
    procedure AfterExecute(); virtual;
    procedure BeforeExecute(); virtual;
    function DatabaseError(const Session: TSSession): TError; virtual;
    procedure DoError(const Error: TError; const Item: TItem; const ShowRetry: Boolean); overload; virtual;
    procedure DoError(const Error: TError; const Item: TItem; const ShowRetry: Boolean; var SQL: string); overload; virtual;
    procedure DoUpdateGUI(); virtual; abstract;
    function NoPrimaryIndexError(const Session: TSSession): TError; virtual;
  public
    Wnd: HWND;
    constructor Create();
    destructor Destroy(); override;
    property ErrorCount: Integer read FErrorCount;
    property Items: TItems read FItems;
    property OnError: TErrorEvent read FOnError write FOnError;
    property OnExecuted: TOnExecuted read FOnExecuted write FOnExecuted;
    property OnUpdate: TOnUpdate read FOnUpdate write FOnUpdate;
    property UserAbort: TEvent read FUserAbort;
  end;

  TTImport = class(TTool)
  type
    TStmtType = (stInsert, stReplace, stUpdate);
    TItem = class(TTool.TItem)
    public
      SourceTableName: string;
      TableName: string;
      constructor Create(const AItems: TTool.TItems);
    end;
  private
    EscapedFieldNames: string;
    FSession: TSSession;
    FDatabase: TSDatabase;
  protected
    procedure AfterExecute(); override;
    procedure AfterExecuteData(const Item: TItem); virtual;
    procedure BeforeExecute(); override;
    procedure BeforeExecuteData(const Item: TItem); virtual;
    procedure Close(); virtual;
    function DoExecuteSQL(const Item: TItem; var SQL: string): Boolean; virtual;
    procedure DoUpdateGUI(); override;
    procedure ExecuteData(const Item: TItem; const Table: TSTable); virtual;
    procedure ExecuteStructure(const Item: TItem); virtual;
    function GetValues(const Item: TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean; overload; virtual;
    function GetValues(const Item: TItem; var Values: TSQLStrings): Boolean; overload; virtual;
    procedure Open(); virtual;
    property Session: TSSession read FSession;
    property Database: TSDatabase read FDatabase;
  public
    Charset: string;
    Collation: string;
    Engine: string;
    Fields: array of TSTableField;
    Data: Boolean;
    Error: Boolean;
    RowType: TMySQLRowType;
    SourceFields: array of record
      Name: string;
    end;
    StmtType: TStmtType;
    Structure: Boolean;
    procedure Add(const TableName: string; const SourceTableName: string = '');
    constructor Create(const ASession: TSSession; const ADatabase: TSDatabase);
    destructor Destroy(); override;
    procedure Execute(); override;
  end;

  TTImportFile = class(TTImport)
  private
    BytesPerSector: DWord;
    FFilename: TFileName;
    FileBuffer: record
      Mem: PAnsiChar;
      Index: DWord;
      Size: DWord;
    end;
    FFileSize: DWord;
  protected
    BOMLength: TLargeInteger;
    FCodePage: Cardinal;
    FileContent: record
      Str: string;
      Index: Integer;
    end;
    FilePos: TLargeInteger;
    Handle: THandle;
    function DoOpenFile(const Filename: TFileName; out Handle: THandle; out Error: TTool.TError): Boolean; virtual;
    function ReadContent(const NewFilePos: TLargeInteger = -1): Boolean; virtual;
    procedure DoUpdateGUI(); override;
    procedure Open(); override;
    property FileSize: DWord read FFileSize;
  public
    procedure Close(); override;
    constructor Create(const AFilename: TFileName; const ACodePage: Cardinal; const ASession: TSSession; const ADatabase: TSDatabase);
    property CodePage: Cardinal read FCodePage;
    property Filename: TFileName read FFilename;
  end;

  TTImportSQL = class(TTImportFile)
  private
    FSetNamesApplied: Boolean;
  public
    Text: PString;
    constructor Create(const AFilename: TFileName; const ACodePage: Cardinal; const ASession: TSSession; const ADatabase: TSDatabase);
    procedure Execute(); overload; override;
    property SetNamesApplied: Boolean read FSetNamesApplied;
  end;

  TTImportText = class(TTImportFile)
  private
    CSVColumns: array of Integer;
    CSVValues: TCSVValues;
    FileFields: array of record
      Name: string;
      FieldTypes: set of Byte;
    end;
    CSVUnquoteMem: PChar;
    CSVUnquoteMemSize: Integer;
    function GetHeadlineNameCount(): Integer;
    function GetHeadlineName(Index: Integer): string;
  protected
    procedure AfterExecuteData(const Item: TTImport.TItem); override;
    procedure BeforeExecuteData(const Item: TTImport.TItem); override;
    procedure ExecuteStructure(const Item: TTImport.TItem); override;
    function GetValues(const Item: TTImport.TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean; override;
    function GetValues(const Item: TTImport.TItem; var Values: TSQLStrings): Boolean; overload; override;
  public
    Delimiter: Char;
    Quoter: Char;
    UseHeadline: Boolean;
    procedure Close(); override;
    constructor Create(const AFilename: TFileName; const ACodePage: Cardinal; const ASession: TSSession; const ADatabase: TSDatabase);
    destructor Destroy(); override;
    function GetPreviewValues(var Values: TSQLStrings): Boolean; virtual;
    procedure Open(); override;
    procedure Reset();
    property HeadlineNameCount: Integer read GetHeadlineNameCount;
    property HeadlineNames[Index: Integer]: string read GetHeadlineName;
  end;

  TTImportBaseODBC = class(TTImport)
  private
    ColumnDesc: array of record
      ColumnName: PSQLTCHAR;
      SQLDataType: SQLSMALLINT;
      MaxDataSize: SQLUINTEGER;
      DecimalDigits: SQLSMALLINT;
      Nullable: SQLSMALLINT;
      SQL_C_TYPE: SQLSMALLINT;
    end;
    ODBCData: SQLPOINTER;
    ODBCMem: Pointer;
    ODBCMemSize: Integer;
    Stmt: SQLHANDLE;
  protected
    FHandle: SQLHDBC;
    procedure AfterExecuteData(const Item: TTImport.TItem); override;
    procedure BeforeExecute(); override;
    procedure BeforeExecuteData(const Item: TTImport.TItem); override;
    function GetValues(const Item: TTImport.TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean; override;
    function GetValues(const Item: TTImport.TItem; var Values: TSQLStrings): Boolean; overload; override;
    procedure ExecuteStructure(const Item: TTImport.TItem); override;
    function ODBCStmtException(const AStmt: SQLHSTMT): Exception;
    property Handle: SQLHDBC read FHandle;
  public
    procedure Close(); override;
    constructor Create(const ASession: TSSession; const ADatabase: TSDatabase);
    destructor Destroy(); override;
    function GetFieldNames(const TableName: string; const FieldNames: TStrings): Boolean; virtual;
    function GetTableNames(const TableNames: TStrings): Boolean; virtual;
  end;

  TTImportODBC = class(TTImportBaseODBC)
  private
    FDataSource: string;
    FPassword: string;
    FUsername: string;
  public
    constructor Create(const ASession: TSSession; const ADatabase: TSDatabase; const ADataSource, AUsername, APassword: string);
    procedure Open(); override;
  end;

  TTImportAccess = class(TTImportBaseODBC)
  private
    FFilename: string;
  public
    constructor Create(const ASession: TSSession; const ADatabase: TSDatabase; const AFilename: string);
    procedure Open(); override;
  end;

  TTImportExcel = class(TTImportBaseODBC)
  private
    FFilename: string;
  public
    constructor Create(const ASession: TSSession; const ADatabase: TSDatabase; const AFilename: string);
    procedure Open(); override;
  end;

  TTImportXML = class(TTImport)
  private
    Filename: string;
    XMLDocument: IXMLDOMDocument;
    XMLNode: IXMLDOMNode;
  protected
    procedure BeforeExecute(); override;
    procedure BeforeExecuteData(const Item: TTImport.TItem); override;
    function GetValues(const Item: TTImport.TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean; override;
    function GetValues(const Item: TTImport.TItem; var Values: TSQLStrings): Boolean; overload; override;
  public
    constructor Create(const AFilename: TFileName; const ATable: TSBaseTable);
  end;

  TTExport = class(TTool)
  type
    TDataSetItem = class(TTool.TItem)
    private
      FDataSet: TMySQLDataSet;
    public
      constructor Create(const AItems: TTool.TItems; const ADataSet: TMySQLDataSet);
      property DataSet: TMySQLDataSet read FDataSet;
    end;
  private
    FSession: TSSession;
  protected
    procedure AfterExecute(); override;
    procedure BeforeExecute(); override;
    procedure DoUpdateGUI(); override;
    procedure ExecuteDatabaseFooter(const Database: TSDatabase); virtual;
    procedure ExecuteDatabaseHeader(const Database: TSDatabase); virtual;
    procedure ExecuteDataSet(const Item: TDataSetItem); virtual;
    procedure ExecuteEvent(const Event: TSEvent); virtual;
    procedure ExecuteFooter(); virtual;
    procedure ExecuteHeader(); virtual;
    procedure ExecuteRoutine(const Routine: TSRoutine); virtual;
    procedure ExecuteTable(const Item: TTool.TDBObjectItem; const DataHandle: TMySQLConnection.TDataResult); virtual;
    procedure ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); virtual;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); virtual;
    procedure ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); virtual;
    procedure ExecuteTrigger(const Trigger: TSTrigger); virtual;
  public
    Data: Boolean;
    DestinationFields: array of record
      Name: string;
    end;
    Fields: array of TField;
    Structure: Boolean;
    TableFields: array of TSTableField;
    procedure Add(const ADataSet: TMySQLDataSet); overload; virtual;
    procedure Add(const ADBObject: TSDBObject); overload; inline;
    constructor Create(const ASession: TSSession);
    procedure Execute(); override;
    property Session: TSSession read FSession;
  end;

  TTExportFile = class(TTExport)
  private
    ContentBuffer: TTool.TStringBuffer;
    FCodePage: Cardinal;
    FileBuffer: record
      Mem: PAnsiChar;
      Size: Cardinal;
    end;
    FFilename: TFileName;
    Handle: THandle;
    procedure Flush();
  protected
    procedure CloseFile(); virtual;
    procedure DoFileCreate(const Filename: TFileName); virtual;
    function FileCreate(const Filename: TFileName; out Error: TTool.TError): Boolean; virtual;
    procedure WriteContent(const Content: string); virtual;
  public
    constructor Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
    destructor Destroy(); override;
    property CodePage: Cardinal read FCodePage;
    property Filename: TFileName read FFilename;
  end;

  TTExportSQL = class(TTExportFile)
  private
    SQLInsertPacketLen: Integer;
    SQLInsertPostfix: string;
    SQLInsertPostfixPacketLen: Integer;
    SQLInsertPrefix: string;
    SQLInsertPrefixPacketLen: Integer;
  protected
    procedure BeforeExecute(); override;
    procedure ExecuteDatabaseHeader(const Database: TSDatabase); override;
    procedure ExecuteEvent(const Event: TSEvent); override;
    procedure ExecuteFooter(); override;
    procedure ExecuteHeader(); override;
    procedure ExecuteRoutine(const Routine: TSRoutine); override;
    procedure ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTrigger(const Trigger: TSTrigger); override;
    function FileCreate(const Filename: TFileName; out Error: TTool.TError): Boolean; override;
  public
    CreateDatabaseStmts: Boolean;
    DisableKeys: Boolean;
    DropStmts: Boolean;
    ReplaceData: Boolean;
    UseDatabaseStmts: Boolean;
    constructor Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
  end;

  TTExportText = class(TTExportFile)
  private
    TempFilename: string;
    Zip: TZipFile;
  protected
    procedure AfterExecute(); override;
    procedure BeforeExecute(); override;
    procedure ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    function FileCreate(const Filename: TFileName; out Error: TTool.TError): Boolean; override;
  public
    Quoter: Char;
    Delimiter: string;
    QuoteStringValues: Boolean;
    QuoteValues: Boolean;
    constructor Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
    destructor Destroy(); override;
  end;

  TTExportUML = class(TTExportFile)
  protected
    procedure ExecuteHeader(); override;
  end;

  TTExportHTML = class(TTExportUML)
  private
    CSS: array of string;
    FieldOfPrimaryIndex: array of Boolean;
    Font: TFont;
    SQLFont: TFont;
    RowOdd: Boolean;
    function EscapeSQL(const SQL: string): string;
  protected
    procedure ExecuteDatabaseHeader(const Database: TSDatabase); override;
    procedure ExecuteEvent(const Event: TSEvent); override;
    procedure ExecuteFooter(); override;
    procedure ExecuteHeader(); override;
    procedure ExecuteRoutine(const Routine: TSRoutine); override;
    procedure ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTrigger(const Trigger: TSTrigger); override;
  public
    TextContent: Boolean;
    NULLText: Boolean;
    RowBackground: Boolean;
    constructor Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
    destructor Destroy(); override;
  end;

  TTExportXML = class(TTExportUML)
  private
  protected
    procedure ExecuteDatabaseFooter(const Database: TSDatabase); override;
    procedure ExecuteDatabaseHeader(const Database: TSDatabase); override;
    procedure ExecuteFooter(); override;
    procedure ExecuteHeader(); override;
    procedure ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
  public
    DatabaseNodeText, DatabaseNodeAttribute: string;
    FieldNodeText, FieldNodeAttribute: string;
    RecordNodeText: string;
    RootNodeText: string;
    TableNodeText, TableNodeAttribute: string;
    constructor Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
  end;

  TTExportBaseODBC = class(TTExport)
  private
    FStmt: SQLHSTMT;
    Parameter: array of record
      Buffer: SQLPOINTER;
      BufferSize: SQLINTEGER;
      Size: SQLINTEGER;
    end;
  protected
    FHandle: SQLHDBC;
    TableName: string;
    constructor Create(const ASession: TSSession; const AHandle: SQLHDBC = SQL_NULL_HANDLE); overload;
    procedure ExecuteFooter(); override;
    procedure ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    property Stmt: SQLHSTMT read FStmt;
  public
    property Handle: SQLHDBC read FHandle;
  end;

  TTExportODBC = class(TTExportBaseODBC)
  private
    FDataSource: string;
    FPassword: string;
    FUsername: string;
  protected
    procedure ExecuteFooter(); override;
    procedure ExecuteHeader(); override;
  public
    constructor Create(const ASession: TSSession; const ADataSource, AUsername, APassword: string); overload;
  end;

  TTExportAccess = class(TTExportBaseODBC)
  private
    Filename: TFileName;
  protected
    procedure ExecuteFooter(); override;
    procedure ExecuteHeader(); override;
  public
    Access2007: Boolean;
    constructor Create(const ASession: TSSession; const AFilename: TFileName);
  end;

  TTExportExcel = class(TTExportBaseODBC)
  private
    Filename: TFileName;
    Sheet: Integer;
  protected
    procedure ExecuteFooter(); override;
    procedure ExecuteHeader(); override;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
  public
    Excel2007: Boolean;
    constructor Create(const ASession: TSSession; const AFilename: TFileName);
  end;

  TTExportCanvas = class(TTExport)
  type
    TColumn = record
      Canvas: TCanvas;
      HeaderBold: Boolean;
      HeaderText: string;
      Left: Integer;
      Rect: TRect;
      Width: Integer;
    end;
    TGridData = array of array of record
      Bold: Boolean;
      Gray: Boolean;
      Text: string;
    end;
  const
    PaddingMilliInch = 20;
    LineHeightMilliInch = 10;
    LineWidthMilliInch = 10;
    MarginsMilliInch: TRect = (Left: 1000; Top: 500; Right: 500; Bottom: 500);
  private
    Columns: array of TColumn;
    ContentArea: TRect;
    ContentFont: TFont;
    DateTime: TDateTime;
    GridFont: TFont;
    GridTop: Integer;
    MaxFieldsCharLengths: array of array of Integer;
    PageFont: TFont;
    PageNumber: record Row, Column: Integer; end;
    SQLFont: TFont;
    Y: Integer;
    function AllocateHeight(const Height: Integer; const DrawGridVertLines: Boolean = True): Boolean;
    procedure ContentTextOut(const Text: string; const ExtraPadding: Integer = 0);
    procedure GridDrawHorzLine(const Y: Integer);
    procedure GridDrawVertLines();
    procedure GridHeader();
    procedure GridOut(var GridData: TGridData);
    function GridTextOut(var Column: TColumn; const Text: string; const TextFormat: TTextFormat; const Bold, Gray: Boolean): Integer;
    procedure PageBreak(const NewPageRow: Boolean);
    procedure PageFooter();
    procedure SetFont(const Font: TFont; const Size: Integer = -1; const Style: TFontStyles = []);
  protected
    Canvas: TCanvas;
    LineHeight: Integer;
    LineWidth: Integer;
    Margins: TRect;
    Padding: Integer;
    PageHeight: Integer;
    PageWidth: Integer;
    procedure AddPage(const NewPageRow: Boolean); virtual; abstract;
    procedure BeforeExecute(); override;
    procedure ExecuteDatabaseHeader(const Database: TSDatabase); override;
    procedure ExecuteEvent(const Event: TSEvent); override;
    procedure ExecuteFooter(); override;
    procedure ExecuteRoutine(const Routine: TSRoutine); override;
    procedure ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery); override;
    procedure ExecuteTrigger(const Trigger: TSTrigger); override;
  public
    IndexBackground: Boolean;
    NULLText: Boolean;
    constructor Create(const ASession: TSSession);
    destructor Destroy(); override;
  end;

  TTExportPrint = class(TTExportCanvas)
  private
    Handle: HDC;
    DevMode: PDeviceMode;
    Pages: array of TBitmap;
    Printer: THandle;
    FTitle: string;
    procedure PrintPage(const Page: TBitmap);
  protected
    procedure AddPage(const NewPageRow: Boolean); override;
    procedure AfterExecute(); override;
    procedure BeforeExecute(); override;
  public
    constructor Create(const ASession: TSSession; const APrinterName: string; const ATitle: string);
    destructor Destroy(); override;
  end;

  TTExportPDF = class(TTExportCanvas)
  private
    PDF: TPDFDocumentGDI;
    Filename: TFileName;
  protected
    procedure AddPage(const NewPageRow: Boolean); override;
    procedure ExecuteHeader(); override;
    procedure ExecuteFooter(); override;
  public
    constructor Create(const ASession: TSSession; const AFilename: TFileName);
    destructor Destroy(); override;
  end;

  TTTransfer = class(TTExport)
  type
    TItem = class(TTool.TDBObjectItem)
    public
      DestinationDatabaseName: string;
      constructor Create(const AItems: TTool.TItems; const ADBObject: TSDBObject);
    end;
  private
    FDestinationSession: TSSession;
    OLD_FOREIGN_KEY_CHECKS: string;
    OLD_UNIQUE_CHECKS: string;
    function DoExecuteSQL(const Session: TSSession; var SQL: string): Boolean;
  protected
    procedure AfterExecute(); override;
    procedure BeforeExecute(); override;
    procedure ExecuteTable(const Item: TTool.TDBObjectItem; const DataHandle: TMySQLConnection.TDataResult); override;
    procedure ExecuteTableData(const Item: TItem; const DataHandle: TMySQLConnection.TDataResult);
    procedure ExecuteTableStructure(const Item: TItem);
  public
    procedure Add(const ADBObject: TSDBObject; const DestinationDatabaseName: string); virtual;
    constructor Create(const ASourceSession, ADestinationSession: TSSession);
    property DestinationSession: TSSession read FDestinationSession;
  end;

  TTSearch = class(TTool)
  type
    TItem = class(TTool.TItem)
    public
      DatabaseName: string;
      FieldNames: array of string;
      RecordsFound: Integer;
      TableName: string;
      constructor Create(const AItems: TTool.TItems);
      destructor Destroy(); override;
    end;
    TOnSearched = procedure(const AItem: TItem) of object;
  private
    FOnSearched: TOnSearched;
    FSession: TSSession;
    procedure BackupTable(const Item: TItem; const Rename: Boolean = False);
  protected
    procedure AfterExecute(); override;
    procedure BeforeExecute(); override;
    function DoExecuteSQL(const Session: TSSession; const Item: TItem; var SQL: string): Boolean; virtual;
    procedure DoUpdateGUI(); override;
    procedure ExecuteDefault(const Item: TItem; const Table: TSBaseTable); virtual;
    procedure ExecuteMatchCase(const Item: TItem; const Table: TSBaseTable); virtual;
    procedure ExecuteWholeValue(const Item: TItem; const Table: TSBaseTable); virtual;
    property Session: TSSession read FSession;
  public
    FindText: string;
    MatchCase: Boolean;
    WholeValue: Boolean;
    RegExpr: Boolean;
    procedure Add(const Table: TSBaseTable; const Field: TSTableField = nil); virtual;
    constructor Create(const ASession: TSSession);
    procedure Execute(); override;
    property OnSearched: TOnSearched read FOnSearched write FOnSearched;
  end;

  TTReplace = class(TTSearch)
  private
    FReplaceSession: TSSession;
  protected
    procedure ExecuteMatchCase(const Item: TTSearch.TItem; const Table: TSBaseTable); override;
    property ReplaceConnection: TSSession read FReplaceSession;
  public
    ReplaceText: string;
    Backup: Boolean;
    constructor Create(const ASession, AReplaceSession: TSSession);
  end;

  EODBCError = EDatabaseError;

function ODBCException(const Stmt: SQLHSTMT; const ReturnCode: SQLRETURN; const AState: PString = nil): SQLRETURN;

const
  CP_UNICODE = 1200;
  BOM_UTF8: PAnsiChar = Chr($EF) + Chr($BB) + Chr($BF);
  BOM_UNICODE_LE: PAnsiChar = Chr($FF) + Chr($FE);

  BackupExtension = '_bak';

var
  ODBCEnv: SQLHENV;
  ODBCDrivers: set of (odAccess, odAccess2007, odExcel, odExcel2007);

implementation {***************************************************************}

uses
  ActiveX, SysConst,
  Forms, DBConsts, Registry, DBCommon, StrUtils, Math, Variants,
  PerlRegEx,
  UMLUtils;

resourcestring
  SSourceParseError = 'Source code of "%s" cannot be analyzed (%d):' + #10#10 + '%s';
  SInvalidQuoter = 'Quoter "%s" not supported for SQL Values import';

const
  SQLPacketSize = 100 * 1024;
  FilePacketSize = 32768;
  ODBCDataSize = 65536;

  daSuccess = daRetry;

  STR_LEN = 128;

  DriverAccess = 'Microsoft Access Driver (*.mdb)';
  DriverAccess2007 = 'Microsoft Access Driver (*.mdb, *.accdb)';
  DriverExcel = 'Microsoft Excel Driver (*.xls)';
  DriverExcel2007 = 'Microsoft Excel Driver (*.xls, *.xlsx, *.xlsm, *.xlsb)';

function GetTempFileName(): string;
var
  FilenameP: array [0 .. MAX_PATH] of Char;
begin
  if ((GetTempPath(MAX_PATH, @FilenameP) > 0) and (Windows.GetTempFileName(FilenameP, '~MF', 0, FilenameP) <> 0)) then
    Result := StrPas(PChar(@FilenameP[0]))
  else
    Result := '';
end;

function GetUTCDateTime(Date: TDateTime): string;
const
  EnglishShortMonthNames : array[1..12] of string
    = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  EnglishShortDayNames : array[1..7] of string
    = ('Sun', 'Mon', 'Thu', 'Wed', 'Thu', 'Fri', 'Sat');
const
  TIME_ZONE_ID_UNKNOWN = 0;
  TIME_ZONE_ID_STANDARD = 1;
  TIME_ZONE_ID_DAYLIGHT = 2;
var
  Day: Byte;
  Month: Byte;
  S: string;
  TempShortDayNames: array[1..12] of string;
  TempShortMonthNames: array[1..12] of string;
  TimeZoneInformation: TTimeZoneInformation;
  TZIBias: Integer;
  TZIName: string;
begin
  case GetTimeZoneInformation(TimeZoneInformation) of
    TIME_ZONE_ID_STANDARD:
      begin
        TZIName := TimeZoneInformation.StandardName;
        TZIBias := TimeZoneInformation.Bias + TimeZoneInformation.StandardBias;
      end;
    TIME_ZONE_ID_DAYLIGHT:
      begin
        TZIName := TimeZoneInformation.DaylightName;
        TZIBias := TimeZoneInformation.Bias + TimeZoneInformation.DaylightBias;
      end;
    else
      begin
        TZIName := '';
        TZIBias := TimeZoneInformation.Bias;
      end;
  end;
  S := TimeToStr(EncodeTime(Abs(TZIBias div 60), Abs(TZIBias mod 60), 0, 0), FileFormatSettings);
  S := Copy(S, 1, 2) + Copy(S, 4, 2);
  if TZIBias>0 then S := '-' + S else S := '+' + S;
  for Month := 1 to 12 do TempShortMonthNames[Month] := FormatSettings.ShortMonthNames[Month];
  for Month := 1 to 12 do FormatSettings.ShortMonthNames[Month] := EnglishShortMonthNames[Month];
  for Day := 1 to 7 do TempShortDayNames[Day] := FormatSettings.ShortDayNames[Day];
  for Day := 1 to 7 do FormatSettings.ShortDayNames[Day] := EnglishShortDayNames[Day];
  S := FormatDateTime('ddd, dd mmm yyyy hh:nn:ss "' + S + '"', Now());
  for Day := 1 to 7 do FormatSettings.ShortDayNames[Day] := TempShortDayNames[Day];
  for Month := 1 to 12 do FormatSettings.ShortMonthNames[Month] := TempShortMonthNames[Month];
  if (Pos('(', TZIName)>0) and (Pos(')', TZIName)>0) then
    S := S + ' ' + Copy(TZIName, Pos('(', TZIName), Pos(')', TZIName)-Pos('(', TZIName) + 1);
  Result := S;
end;

function ODBCError(const HandleType: SQLSMALLINT; const Handle: SQLHANDLE): TTool.TError;
var
  cbMessageText: SQLSMALLINT;
  MessageText: PSQLTCHAR;
  SQLState: array [0 .. SQL_SQLSTATE_SIZE] of SQLTCHAR;
begin
  Result.ErrorType := TE_ODBC;
  Result.ErrorCode := 0;
  case (SQLGetDiagRec(HandleType, Handle, 1, @SQLState, nil, nil, 0, @cbMessageText)) of
    SQL_ERROR:
      raise Exception.Create('Unknown ODBC Error');
    SQL_SUCCESS,
    SQL_SUCCESS_WITH_INFO:
      begin
        GetMem(MessageText, (cbMessageText + 1) * SizeOf(SQLTCHAR));
        SQLGetDiagRec(HandleType, Handle, 1, nil, nil, MessageText, cbMessageText + 1, nil);
        Result.ErrorMessage := PChar(MessageText) + ' (' + SQLState + ')';
        FreeMem(MessageText);
      end;
    SQL_INVALID_HANDLE:
      Result.ErrorMessage := 'Invalid ODBC Handle.';
    SQL_NO_DATA:
      raise Exception.Create('Unknown ODBC Error (No Data)');
  end;
end;

function ODBCException(const Stmt: SQLHSTMT; const ReturnCode: SQLRETURN; const AState: PString = nil): SQLRETURN;
var
  cbMessageText: SQLSMALLINT;
  MessageText: PSQLTCHAR;
  Msg: string;
  SQLState: array [0 .. SQL_SQLSTATE_SIZE] of SQLTCHAR;
begin
  ZeroMemory(@SQLState, SizeOf(SQLState));

  if ((ReturnCode < SQL_SUCCESS) or (ReturnCode = SQL_SUCCESS_WITH_INFO)) then
    if (SQLGetDiagRec(SQL_HANDLE_STMT, Stmt, 1, @SQLState, nil, nil, 0, @cbMessageText) = SQL_INVALID_HANDLE) then
      raise Exception.Create('Invalid ODBC Handle')
    else if ((SQLState <> '') and (SQLState <> '01004')) then
    begin
      GetMem(MessageText, (cbMessageText + 1) * SizeOf(SQLTChar));
      SQLGetDiagRec(SQL_HANDLE_STMT, Stmt, 1, nil, nil, MessageText, cbMessageText + 1, nil);
      Msg := PChar(MessageText) + ' (' + SQLState + ')';
      FreeMem(MessageText);
      raise EODBCError.Create(Msg);
    end;

  if (Assigned(AState)) then
    AState^ := SQLState;

  Result := ReturnCode;
end;

function SQLLoadDataInfile(const Database: TSDatabase; const Replace: Boolean; const Filename, FileCharset, DatabaseName, TableName: string; const FieldNames: string): string;
var
  Session: TSSession;
begin
  Session := Database.Session;

  Result := 'LOAD DATA LOCAL INFILE ' + SQLEscape(Filename) + #13#10;
  if (Replace) then
    Result := Result + '  REPLACE' + #13#10;
  Result := Result + '  INTO TABLE ' + Session.EscapeIdentifier(DatabaseName) + '.' + Session.EscapeIdentifier(TableName) + #13#10;
  if (((50038 <= Session.ServerVersion) and (Session.ServerVersion < 50100) or (50117 <= Session.ServerVersion)) and (FileCharset <> '')) then
    Result := Result + '  CHARACTER SET ' + FileCharset + #13#10;
  Result := Result + '  FIELDS' + #13#10;
  Result := Result + '    TERMINATED BY ' + SQLEscape(',') + #13#10;
  Result := Result + '    OPTIONALLY ENCLOSED BY ' + SQLEscape('''') + #13#10;
  Result := Result + '    ESCAPED BY ' + SQLEscape('\') + #13#10;
  Result := Result + '  LINES' + #13#10;
  Result := Result + '    TERMINATED BY ' + SQLEscape(#10) + #13#10;
  if (FieldNames <> '') then
    Result := Result + '  (' + FieldNames + ')' + #13#10;
  Result := SysUtils.Trim(Result) + ';' + #13#10;

  if (((Session.ServerVersion < 50038) or (50100 <= Session.ServerVersion)) and (Session.ServerVersion < 50117) and (FileCharset <> '')) then
    if ((Session.ServerVersion < 40100) or not Assigned(Session.VariableByName('character_set_database'))) then
      Session.Charset := FileCharset
    else if ((Session.VariableByName('character_set_database').Value <> FileCharset) and (Session.LibraryType <> ltHTTP)) then
      Result :=
        'SET SESSION character_set_database=' + SQLEscape(FileCharset) + ';' + #13#10
        + Result
        + 'SET SESSION character_set_database=' + SQLEscape(Session.VariableByName('character_set_database').Value) + ';' + #13#10;
end;

function SysError(): TTool.TError;
begin
  Result.ErrorType := TE_File;
  Result.ErrorCode := GetLastError();
  Result.ErrorMessage := SysErrorMessage(GetLastError());
  Result.Session := nil;
end;

function TToolItemCompare(Item1, Item2: Pointer): Integer;
var
  Index1: Integer;
  Index2: Integer;
begin
  Result := 0;

  if (Item1 <> Item2) then
  begin
    if (TTool.TItem(Item1) is TTExport.TDataSetItem) then
      Index1 := 0
    else
      Index1 := 1;
    if (TTool.TItem(Item2) is TTExport.TDataSetItem) then
      Index2 := 0
    else
      Index2 := 1;
    Result := Sign(Index1 - Index2);

    if ((Result = 0) and (TTool.TItem(Item1) is TTExport.TDBObjectItem)) then
      Result := Sign(TTExport.TDBObjectItem(Item1).DBObject.Database.Index - TTExport.TDBObjectItem(Item2).DBObject.Database.Index);

    if ((Result = 0) and (TTool.TItem(Item1) is TTExport.TDBObjectItem)) then
    begin
      if (TTExport.TDBObjectItem(Item1).DBObject is TSTable) then
        Index1 := 0
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSRoutine) then
        Index1 := 1
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSTrigger) then
        Index1 := 2
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSEvent) then
        Index1 := 3
      else
        Index1 := 4;
      if (TTExport.TDBObjectItem(Item2).DBObject is TSTable) then
        Index2 := 0
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSRoutine) then
        Index2 := 1
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSTrigger) then
        Index2 := 2
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSEvent) then
        Index2 := 3
      else
        Index2 := 4;
      Result := Sign(Index1 - Index2);
    end;

    if (Result = 0) then
      Result := Sign(TTool.TItem(Item1).Index - TTool.TItem(Item2).Index);
  end;
end;

function TToolItemCompareForSQL(Item1, Item2: Pointer): Integer;
var
  Index1: Integer;
  Index2: Integer;
begin
  Result := 0;

  if (Item1 <> Item2) then
  begin
    if (TTool.TItem(Item1) is TTExport.TDataSetItem) then
      Index1 := 0
    else
      Index1 := 1;
    if (TTool.TItem(Item2) is TTExport.TDataSetItem) then
      Index2 := 0
    else
      Index2 := 1;
    Result := Sign(Index1 - Index2);

    if ((Result = 0) and (TTool.TItem(Item1) is TTExport.TDBObjectItem)) then
      Result := Sign(TTExport.TDBObjectItem(Item1).DBObject.Database.Index - TTExport.TDBObjectItem(Item2).DBObject.Database.Index);

    if ((Result = 0) and (TTool.TItem(Item1) is TTExport.TDBObjectItem)) then
    begin
      if (TTExport.TDBObjectItem(Item1).DBObject is TSBaseTable) then
        if (not Assigned(TSBaseTable(TTExport.TDBObjectItem(Item1).DBObject).Engine) or not TSBaseTable(TTExport.TDBObjectItem(Item1).DBObject).Engine.IsMerge) then
          Index1 := 0
        else
          Index1 := 1
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSFunction) then
        Index1 := 2
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSView) then
        Index1 := 3
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSProcedure) then
        Index1 := 4
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSTrigger) then
        Index1 := 5
      else if (TTExport.TDBObjectItem(Item1).DBObject is TSEvent) then
        Index1 := 6
      else
        Index1 := 7;
      if (TTExport.TDBObjectItem(Item2).DBObject is TSBaseTable) then
        if (not Assigned(TSBaseTable(TTExport.TDBObjectItem(Item2).DBObject).Engine) or not TSBaseTable(TTExport.TDBObjectItem(Item2).DBObject).Engine.IsMerge) then
          Index2 := 0
        else
          Index2 := 1
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSFunction) then
        Index2 := 2
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSView) then
        Index2 := 3
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSProcedure) then
        Index2 := 4
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSTrigger) then
        Index2 := 5
      else if (TTExport.TDBObjectItem(Item2).DBObject is TSEvent) then
        Index2 := 6
      else
        Index2 := 7;
      Result := Sign(Index1 - Index2);
    end;

    if (Result = 0) then
      if (TTool.TItem(Item1) is TTExport.TDataSetItem) then
        Result := Sign(TTExport.TDataSetItem(Item1).Index - TTExport.TDataSetItem(Item2).Index)
      else
        Result := Sign(TTExport.TDBObjectItem(Item1).DBObject.Index - TTExport.TDBObjectItem(Item2).DBObject.Index);
  end;
end;

function UMLEncoding(const Codepage: Cardinal): string;
var
  Reg: TRegistry;
begin
  Result := '';

  Reg := TRegistry.Create();
  Reg.RootKey := HKEY_CLASSES_ROOT;
  if (Reg.OpenKey('\MIME\Database\Codepage\' + IntToStr(Codepage), False)) then
  begin
    if (Reg.ValueExists('WebCharset')) then
      Result := Reg.ReadString('WebCharset')
    else if (Reg.ValueExists('BodyCharset')) then
      Result := Reg.ReadString('BodyCharset');
    Reg.CloseKey();
  end;
  Reg.Free();
end;

function ZipError(const Zip: TZipFile; const ErrorMessage: string): TTool.TError;
begin
  Result.ErrorType := TE_File;
  Result.ErrorCode := 0;
  Result.ErrorMessage := ErrorMessage;
  Result.Session := nil;
end;

{ TTool.TDataFileBuffer *******************************************************}

procedure TTool.TDataFileBuffer.Clear();
begin
  Buffer.Write := Buffer.Mem;
end;

constructor TTool.TDataFileBuffer.Create(const ACodePage: Cardinal);
var
  CPInfoEx: TCpInfoEx;
begin
  inherited Create();

  Buffer.Mem := nil;
  Buffer.Size := 0;
  Buffer.Write := nil;
  CodePage := ACodePage;
  Temp1.Mem := nil;
  Temp1.Size := 0;
  Temp2.Mem := nil;
  Temp2.Size := 0;

  if (not GetCPInfoEx(CodePage, 0, CPInfoEx)) then
    RaiseLastOSError()
  else
    MaxCharSize := CPInfoEx.MaxCharSize;

  Resize(2 * NET_BUFFER_LENGTH);
end;

destructor TTool.TDataFileBuffer.Destroy();
begin
  if (Assigned(Buffer.Mem)) then FreeMem(Buffer.Mem);
  if (Assigned(Temp1.Mem)) then FreeMem(Temp1.Mem);
  if (Assigned(Temp2.Mem)) then FreeMem(Temp2.Mem);

  inherited;
end;

function TTool.TDataFileBuffer.GetData(): Pointer;
begin
  Result := Pointer(Buffer.Mem);
end;

function TTool.TDataFileBuffer.GetSize(): Integer;
begin
  Result := Integer(Buffer.Write) - Integer(Buffer.Mem);
end;

procedure TTool.TDataFileBuffer.Write(const Data: Pointer; const Size: Integer; const Quote: Boolean = False);
begin
  if (not Quote) then
  begin
    Resize(Size);
    MoveMemory(Buffer.Write, Data, Size); Buffer.Write := @Buffer.Write[Size];
  end
  else
  begin
    Resize(1 + Size + 1);
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
    MoveMemory(Buffer.Write, Data, Size); Buffer.Write := @Buffer.Write[Size];
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
  end;
end;

procedure TTool.TDataFileBuffer.WriteData(const Text: PChar; const Length: Integer; const Quote: Boolean = False);
label
  StringL,
  Finish;
var
  Len: Integer;
  Write: PAnsiChar;
begin
  if (not Quote) then
    Len := Length
  else
    Len := 1 + Length + 1;

  Resize(Len);

  Write := Buffer.Write;
  asm
        PUSH ES
        PUSH ESI
        PUSH EDI

        PUSH DS                          // string operations uses ES
        POP ES
        CLD                              // string operations uses forward direction

        MOV ESI,Text                     // Copy characters from Text
        MOV EDI,Write                    //   to Write
        MOV ECX,Length                   // Character count

        CMP Quote,False                  // Quote Value?
        JE StringL                       // No!
        MOV AL,''''                      // Starting quoter
        STOSB                            //   into Write

      StringL:
        LODSW                            // Load WideChar from Text
        STOSB                            // Store AnsiChar into Buffer.Mem
        LOOP StringL                     // Repeat for all characters

        CMP Quote,False                  // Quote Value?
        JE Finish                        // No!
        MOV AL,''''                      // Ending quoter
        STOSB                            //   into Write

      Finish:
        POP EDI
        POP ESI
        POP ES
    end;

  Buffer.Write := @Buffer.Write[Len];
end;

procedure TTool.TDataFileBuffer.WriteText(const Text: PChar; const Length: Integer);
var
  Len: Integer;
  Size: Integer;
begin
  Size := (1 + 2 * Length + 1) * SizeOf(Char);
  if (Size > Temp2.Size) then
  begin
    Temp2.Size := Temp2.Size + 2 * (Size - Temp2.Size);
    ReallocMem(Temp2.Mem, Temp2.Size);
  end;
  Len := SQLEscape(Text, Length, PChar(Temp2.Mem), Size);
  if (Len = 0) then
    raise ERangeError.Create(SRangeError);

  Size := MaxCharSize * Len;
  Resize(Size);
  Len := WideCharToAnsiChar(CodePage, PChar(Temp2.Mem), Len, Buffer.Write, Buffer.Size - Self.Size);
  Buffer.Write := @Buffer.Write[Len];
end;

procedure TTool.TDataFileBuffer.WriteText(const Text: my_char; const Length: Integer; const CodePage: Cardinal);
var
  Len: Integer;
  Size: Integer;
begin
  Size := SizeOf(Char) * Length;
  if (Size = 0) then
  begin
    Resize(2);
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
  end
  else
  begin
    if (Size > Temp1.Size) then
    begin
      ReallocMem(Temp1.Mem, Size);
      Temp1.Size := Size;
    end;
    Len := AnsiCharToWideChar(CodePage, Text, Length, PChar(Temp1.Mem), Temp1.Size div SizeOf(Char));
    WriteText(PChar(Temp1.Mem), Len);
  end;
end;

procedure TTool.TDataFileBuffer.WriteBinary(const Value: PChar; const Length: Integer);
label
  StringL;
var
  Len: Integer;
  Read: Pointer;
  Size: Integer;
  Write: my_char;
begin
  if (Length = 0) then
  begin
    Resize(2);
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
  end
  else
  begin
    Len := 1 + 2 * Length + 1;
    Size := Len * SizeOf(Char);
    if (Size > Temp1.Size) then
    begin
      Temp1.Size := Size;
      ReallocMem(Temp1.Mem, Temp1.Size);
    end;
    Len := SQLEscape(Value, Length, PChar(Temp1.Mem), Len);
    if (Len = 0) then
      raise ERangeError.Create(SRangeError);

    Resize(Len);

    Read := Temp1.Mem;
    Write := Buffer.Write;
    asm
        PUSH ES
        PUSH ESI
        PUSH EDI

        PUSH DS                          // string operations uses ES
        POP ES
        CLD                              // string operations uses forward direction

        MOV ESI,Read                     // Copy characters from Temp1.Mem
        MOV EDI,Write                    //   to Buffer.Write
        MOV ECX,Len                      // Character count

      StringL:
        LODSW                            // Load WideChar
        STOSB                            // Store AnsiChar
        LOOP StringL                     // Repeat for all characters

        POP EDI
        POP ESI
        POP ES
    end;
    Buffer.Write := @Buffer.Write[Len];
  end;
end;

procedure TTool.TDataFileBuffer.WriteBinary(const Value: my_char; const Length: Integer);
label
  StringL;
var
  Size: Integer;
  Write: Pointer;
begin
  if (Length = 0) then
  begin
    Resize(2);
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
    Buffer.Write[0] := ''''; Buffer.Write := @Buffer.Write[1];
  end
  else
  begin
    Size := Length * SizeOf(Char);
    if (Size > Temp2.Size) then
    begin
      Temp2.Size := Size;
      ReallocMem(Temp2.Mem, Temp2.Size);
    end;

    Write := Temp2.Mem;
    asm
        PUSH ES
        PUSH ESI
        PUSH EDI

        PUSH DS                          // string operations uses ES
        POP ES
        CLD                              // string operations uses forward direction

        MOV ESI,Value                    // Copy characters from Value
        MOV EDI,Write                    //   to Temp2.Mem
        MOV ECX,Length                   // Character count

        MOV AH,0                         // High-byte for STOSW
      StringL:
        LODSB                            // Load AnsiChar
        STOSW                            // Store WideChar
        LOOP StringL                     // Repeat for all characters

        POP EDI
        POP ESI
        POP ES
    end;

    WriteBinary(PChar(Temp2.Mem), Length);
  end;
end;

procedure TTool.TDataFileBuffer.Resize(const NeededSize: Integer);
var
  Len: Integer;
begin
  if (Buffer.Size = 0) then
  begin
    Buffer.Size := NeededSize;
    GetMem(Buffer.Mem, Buffer.Size);
    Buffer.Write := Buffer.Mem;
  end
  else if (Size + NeededSize > Buffer.Size) then
  begin
    Len := Size;
    Buffer.Size := Buffer.Size + 2 * (Len + NeededSize - Buffer.Size);
    ReallocMem(Buffer.Mem, Buffer.Size);
    Buffer.Write := @Buffer.Mem[Len];
  end;
end;

{ TTool.TItems ****************************************************************}

constructor TTool.TItem.Create(const AItems: TTool.TItems);
begin
  inherited Create();

  FItems := AItems;

  Done := False;
  RecordsDone := 0;
  RecordsSum := 0;
end;

function TTool.TItem.GetIndex(): Integer;
begin
  Result := Items.IndexOf(Self);
end;

{ TTool.TDataSetItem **********************************************************}

constructor TTool.TDBObjectItem.Create(const AItems: TTool.TItems; const ADBObject: TSDBObject);
begin
  inherited Create(AItems);

  FDBObject := ADBObject;
end;

{ TTool.TItems ****************************************************************}

constructor TTool.TItems.Create(const ATool: TTool);
begin
  inherited Create();

  FTool := ATool;
end;

destructor TTool.TItems.Destroy();
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    Item[I].Free();

  inherited;
end;

function TTool.TItems.GetItem(Index: Integer): TItem;
begin
  Result := TItem(Items[Index]);
end;

{ TTool.TStringBuffer *********************************************************}

procedure TTool.TStringBuffer.Clear();
begin
  Buffer.Write := Buffer.Mem;
end;

constructor TTool.TStringBuffer.Create(const MemSize: Integer);
begin
  Buffer.Size := 0;
  Buffer.Mem := nil;
  Buffer.Write := nil;

  Resize(MemSize);
end;

destructor TTool.TStringBuffer.Destroy();
begin
  FreeMem(Buffer.Mem);

  inherited;
end;

function TTool.TStringBuffer.GetData(): Pointer;
begin
  Result := Pointer(Buffer.Mem);
end;

function TTool.TStringBuffer.GetSize(): Integer;
begin
  Result := Integer(Buffer.Write) - Integer(Buffer.Mem);
end;

function TTool.TStringBuffer.Read(): string;
begin
  SetString(Result, PChar(Buffer.Mem), Size div SizeOf(Result[1]));
  Clear();
end;

procedure TTool.TStringBuffer.Resize(const NeededLength: Integer);
var
  Index: Integer;
begin
  if (Buffer.Size = 0) then
  begin
    Buffer.Size := NeededLength * SizeOf(Char);
    GetMem(Buffer.Mem, Buffer.Size);
    Buffer.Write := Buffer.Mem;
  end
  else if (Size + NeededLength * SizeOf(Char) > Buffer.Size) then
  begin
    Index := Size * SizeOf(Buffer.Write[0]);
    Inc(Buffer.Size, 2 * (Size + NeededLength * SizeOf(Char) - Buffer.Size));
    ReallocMem(Buffer.Mem, Buffer.Size);
    Buffer.Write := @Buffer.Mem[Index];
  end;
end;

procedure TTool.TStringBuffer.Write(const Text: string);
var
  Size: Integer;
begin
  Size := System.Length(Text) * SizeOf(Text[1]);

  if (Size > 0) then
  begin
    Resize(Size);

    MoveMemory(Buffer.Write, PChar(Text), Size);
    Buffer.Write := @Buffer.Write[System.Length(Text)];
  end;
end;

{ TTools **********************************************************************}

procedure TTool.AfterExecute();
begin
  DoUpdateGUI();

  if (Assigned(OnExecuted)) then
    OnExecuted(Success = daSuccess);
end;

procedure TTool.BeforeExecute();
begin
  StartTime := Now();
  Success := daSuccess;

  DoUpdateGUI();
end;

constructor TTool.Create();
begin
  inherited Create(True);

  Success := daSuccess;

  CriticalSection := TCriticalSection.Create();
  FErrorCount := 0;
  FItems := TItems.Create(Self);
  FUserAbort := TEvent.Create(nil, True, False, '');
end;

function TTool.DatabaseError(const Session: TSSession): TTool.TError;
begin
  Result.ErrorType := TE_Database;
  Result.ErrorCode := Session.ErrorCode;
  Result.ErrorMessage := Session.ErrorMessage;
  Result.Session := Session;
end;

destructor TTool.Destroy();
begin
  CriticalSection.Free();
  FItems.Free();
  FUserAbort.Free();

  inherited;
end;

procedure TTool.DoError(const Error: TTool.TError; const Item: TTool.TItem; const ShowRetry: Boolean);
var
  ErrorTime: TDateTime;
begin
  Inc(FErrorCount);
  if (Success <> daAbort) then
    if (not Assigned(OnError)) then
      Success := daAbort
    else
    begin
      ErrorTime := Now();
      OnError(Self, Error, Item, ShowRetry, Success);
      StartTime := StartTime + ErrorTime - Now();
    end;
end;

procedure TTool.DoError(const Error: TTool.TError; const Item: TTool.TItem; const ShowRetry: Boolean; var SQL: string);
begin
  DoError(Error, Item, ShowRetry);
  if (Success = daFail) then
  begin
    Delete(SQL, 1, SQLStmtLength(PChar(SQL), Length(SQL)));
    Success := daSuccess;
  end;
end;

function TTool.NoPrimaryIndexError(const Session: TSSession): TTool.TError;
begin
  Result.ErrorType := TE_NoPrimaryIndex;
  Result.ErrorCode := -1;
  Result.ErrorMessage := '';
  Result.Session := Session;
end;

{ TTImport.TItem **************************************************************}

constructor TTImport.TItem.Create(const AItems: TTool.TItems);
begin
  inherited;

  SourceTableName := '';
  TableName := '';
end;

{ TTImport ********************************************************************}

procedure TTImport.Add(const TableName: string; const SourceTableName: string = '');
var
  NewItem: TTImport.TItem;
begin
  NewItem := TTImport.TItem.Create(Items);

  NewItem.TableName := TableName;
  NewItem.SourceTableName := SourceTableName;

  Items.Add(NewItem);
end;

procedure TTImport.AfterExecute();
begin
  Session.EndSilent();

  inherited;
end;

procedure TTImport.AfterExecuteData(const Item: TItem);
begin
end;

procedure TTImport.BeforeExecute();
begin
  inherited;

  Session.BeginSilent();
end;

procedure TTImport.BeforeExecuteData(const Item: TItem);
var
  I: Integer;
begin
  EscapedFieldNames := '';
  if (not Structure and (Length(Fields) > 0)) then
    for I := 0 to Length(Fields) - 1 do
    begin
      if (I > 0) then EscapedFieldNames := EscapedFieldNames + ',';
      EscapedFieldNames := EscapedFieldNames + Session.EscapeIdentifier(Fields[I].Name);
    end;
end;

procedure TTImport.Close();
begin
end;

constructor TTImport.Create(const ASession: TSSession; const ADatabase: TSDatabase);
begin
  inherited Create();

  FSession := ASession;
  FDatabase := ADatabase;

  Data := False;
  Structure := False;
end;

destructor TTImport.Destroy();
begin
  Close();

  inherited;
end;

function TTImport.DoExecuteSQL(const Item: TItem; var SQL: string): Boolean;
begin
  Result := Session.ExecuteSQL(SQL);
  if (Result) then
    SQL := ''
  else
  begin
    Delete(SQL, 1, Session.ExecutedSQLLength);
    SQL := SysUtils.Trim(SQL);
  end;
end;

procedure TTImport.DoUpdateGUI();
var
  I: Integer;
begin
  CriticalSection.Enter();

  ProgressInfos.TablesDone := 0;
  ProgressInfos.TablesSum := Items.Count;
  ProgressInfos.RecordsDone := 0;
  ProgressInfos.RecordsSum := 0;
  ProgressInfos.TimeDone := 0;
  ProgressInfos.TimeSum := 0;

  for I := 0 to Items.Count - 1 do
  begin
    if (Items[I].Done) then
      Inc(ProgressInfos.TablesDone);

    Inc(ProgressInfos.RecordsDone, Items[I].RecordsDone);
    Inc(ProgressInfos.RecordsSum, Items[I].RecordsSum);
  end;

  ProgressInfos.TimeDone := Now() - StartTime;

  if ((ProgressInfos.RecordsDone = 0) and (ProgressInfos.TablesDone = 0)) then
  begin
    ProgressInfos.Progress := 0;
    ProgressInfos.TimeSum := 0;
  end
  else if (ProgressInfos.RecordsDone = 0) then
  begin
    ProgressInfos.Progress := Round(ProgressInfos.TablesDone / ProgressInfos.TablesSum * 100);
    ProgressInfos.TimeSum := ProgressInfos.TimeDone / ProgressInfos.TablesDone * ProgressInfos.TablesSum;
  end
  else if (ProgressInfos.RecordsDone < ProgressInfos.RecordsSum) then
  begin
    ProgressInfos.Progress := Round(ProgressInfos.RecordsDone / ProgressInfos.RecordsSum * 100);
    ProgressInfos.TimeSum := ProgressInfos.TimeDone / ProgressInfos.RecordsDone * ProgressInfos.RecordsSum;
  end
  else
  begin
    ProgressInfos.Progress := 100;
    ProgressInfos.TimeSum := ProgressInfos.TimeDone;
  end;

  CriticalSection.Leave();

  if (Assigned(FOnUpdate)) then
    FOnUpdate(ProgressInfos);
end;

procedure TTImport.Execute();
var
  DataSet: TMySQLQuery;
  I: Integer;
  OLD_FOREIGN_KEY_CHECKS: string;
  OLD_UNIQUE_CHECKS: string;
  SQL: string;
begin
  {$IFDEF EurekaLog}
  try
  {$ENDIF}

  BeforeExecute();

  Open();

  if (Data and (Session.ServerVersion >= 40014)) then
  begin
    if (Assigned(Session.VariableByName('UNIQUE_CHECKS'))
      and Assigned(Session.VariableByName('FOREIGN_KEY_CHECKS'))) then
    begin
      OLD_UNIQUE_CHECKS := Session.VariableByName('UNIQUE_CHECKS').Value;
      OLD_FOREIGN_KEY_CHECKS := Session.VariableByName('FOREIGN_KEY_CHECKS').Value;
    end
    else
    begin
      DataSet := TMySQLQuery.Create(nil);
      DataSet.Connection := Session;
      DataSet.CommandText := 'SELECT @@UNIQUE_CHECKS,@@FOREIGN_KEY_CHECKS';

      while ((Success <> daAbort) and not DataSet.Active) do
      begin
        DataSet.Open();
        if (Session.ErrorCode > 0) then
          DoError(DatabaseError(Session), nil, True, SQL);
      end;

      if (DataSet.Active) then
      begin
        OLD_UNIQUE_CHECKS := DataSet.Fields[0].AsString;
        OLD_FOREIGN_KEY_CHECKS := DataSet.Fields[1].AsString;
        DataSet.Close();
      end;

      DataSet.Free();
    end;

    SQL := 'SET UNIQUE_CHECKS=0,FOREIGN_KEY_CHECKS=0;';
    while ((Success <> daAbort) and not Session.ExecuteSQL(SQL)) do
      DoError(DatabaseError(Session), nil, True, SQL);
  end;

  for I := 0 to Items.Count - 1 do
    if (Success <> daAbort) then
    begin
      Success := daSuccess;

      if (Structure) then
      begin
        if (Assigned(Database.TableByName(TTImport.TItem(Items[I]).TableName))) then
        begin
          Session.BeginSynchron();
          while ((Success <> daAbort) and not Database.DeleteObject(Database.TableByName(TTImport.TItem(Items[I]).TableName))) do
            DoError(DatabaseError(Session), Items[I], True);
          Session.EndSynchron();
        end;
        if (Success = daSuccess) then
          ExecuteStructure(TTImport.TItem(Items[I]));
      end;

      if ((Success = daSuccess) and Data) then
      begin
        if (not Assigned(Database.TableByName(TTImport.TItem(Items[I]).TableName))) then
          raise Exception.Create('Table "' + TTImport.TItem(Items[I]).TableName + '" does not exists.');
        ExecuteData(TTImport.TItem(Items[I]), Database.TableByName(TTImport.TItem(Items[I]).TableName));
      end;

      Items[I].Done := True;
    end;

  if (Data and (Session.ServerVersion >= 40014)) then
  begin
    SQL := 'SET UNIQUE_CHECKS=' + OLD_UNIQUE_CHECKS + ',FOREIGN_KEY_CHECKS=' + OLD_FOREIGN_KEY_CHECKS + ';' + #13#10;
    while (not Session.ExecuteSQL(SQL) and (Success = daSuccess)) do
      DoError(DatabaseError(Session), nil, True, SQL);
  end;

  AfterExecute();

  {$IFDEF EurekaLog}
  except
    StandardEurekaNotify(GetLastExceptionObject(), GetLastExceptionAddress());
  end;
  {$ENDIF}
end;

procedure TTImport.ExecuteData(const Item: TItem; const Table: TSTable);
var
  BytesWritten: DWord;
  DataSet: TMySQLQuery;
  DataFileBuffer: TDataFileBuffer;
  DBValues: RawByteString;
  Error: TTool.TError;
  EscapedFieldName: array of string;
  EscapedTableName: string;
  I: Integer;
  InsertStmtInSQL: Boolean;
  Pipe: THandle;
  Pipename: string;
  SQL: string;
  SQLExecuted: TEvent;
  SQLExecuteLength: Integer;
  SQLValues: TSQLStrings;
  Values: string;
  WhereClausel: string;
begin
  BeforeExecuteData(Item);

  EscapedTableName := Session.EscapeIdentifier(Table.Name);

  if (Success = daSuccess) then
  begin
    SQLExecuted := TEvent.Create(nil, False, False, '');

    SQL := '';
    if (Session.DatabaseName <> Database.Name) then
      SQL := SQL + Database.SQLUse() + #13#10;
    if (Structure) then
    begin
      SQL := SQL + 'LOCK TABLES ' + EscapedTableName + ' WRITE;' + #13#10;
      if ((Session.ServerVersion >= 40000) and (Table is TSBaseTable) and TSBaseTable(Table).Engine.IsMyISAM) then
        SQL := SQL + 'ALTER TABLE ' + EscapedTableName + ' DISABLE KEYS;' + #13#10;
    end;
    if (Session.Lib.LibraryType <> ltHTTP) then
      if (Session.ServerVersion < 40011) then
        SQL := SQL + 'BEGIN;' + #13#10
      else
        SQL := SQL + 'START TRANSACTION;' + #13#10;

    if ((StmtType <> stUpdate) and Session.DataFileAllowed and not Suspended) then
    begin
      Pipename := '\\.\pipe\' + LoadStr(1000);
      Pipe := CreateNamedPipe(PChar(Pipename),
                              PIPE_ACCESS_OUTBOUND, PIPE_TYPE_MESSAGE or PIPE_READMODE_BYTE or PIPE_WAIT,
                              1, 2 * NET_BUFFER_LENGTH, 0, 0, nil);
      if (Pipe = INVALID_HANDLE_VALUE) then
        DoError(SysError(), nil, False)
      else
      begin
        SQL := SQL + SQLLoadDataInfile(Database, StmtType = stReplace, Pipename, Session.Charset, Database.Name, Table.Name, EscapedFieldNames);

        Session.SendSQL(SQL, SQLExecuted);

        if (ConnectNamedPipe(Pipe, nil)) then
        begin
          DataFileBuffer := TDataFileBuffer.Create(Session.CodePage);

          Item.RecordsDone := 0;
          while ((Success = daSuccess) and GetValues(Item, DataFileBuffer)) do
          begin
            DataFileBuffer.Write(PAnsiChar(#10 + '_'), 1); // Two characters are needed to instruct the compiler to give a pointer - but the first character should be placed in the file only

            if (DataFileBuffer.Size > NET_BUFFER_LENGTH) then
              if (not WriteFile(Pipe, DataFileBuffer.Data^, DataFileBuffer.Size, BytesWritten, nil)) then
                DoError(SysError(), nil, False)
              else
                DataFileBuffer.Clear();

            Inc(Item.RecordsDone);
            if (Item.RecordsDone mod 100 = 0) then DoUpdateGUI();

            if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
              Success := daAbort;
          end;

          if (DataFileBuffer.Size > 0) then
            if (not WriteFile(Pipe, DataFileBuffer.Data^, DataFileBuffer.Size, BytesWritten, nil)) then
              DoError(SysError(), nil, False)
            else
              DataFileBuffer.Clear();

          if (FlushFileBuffers(Pipe) and WriteFile(Pipe, PAnsiChar(DBValues)^, 0, BytesWritten, nil) and FlushFileBuffers(Pipe)) then
            SQLExecuted.WaitFor(INFINITE);
          DisconnectNamedPipe(Pipe);

          if ((Success = daSuccess) and (StmtType = stInsert) and (Session.WarningCount > 0)) then
          begin
            DataSet := TMySQLQuery.Create(nil);
            DataSet.Connection := Session;
            DataSet.CommandText := 'SHOW WARNINGS';

            DataSet.Open();
            if (DataSet.Active and not DataSet.IsEmpty()) then
            begin
              Error.ErrorType := TE_Warning;
              Error.ErrorCode := 1;
              repeat
                Error.ErrorMessage := Error.ErrorMessage + SysUtils.Trim(DataSet.FieldByName('Message').AsString) + #13#10;
              until (not DataSet.FindNext());
              DoError(Error, Item, False);
            end;
            DataSet.Free();
          end;

          if (Session.ErrorCode <> 0) then
            DoError(DatabaseError(Session), Item, False, SQL);

          SQL := '';
          if (Structure) then
          begin
            if ((Session.ServerVersion >= 40000) and (Table is TSBaseTable) and TSBaseTable(Table).Engine.IsMyISAM) then
              SQL := SQL + 'ALTER TABLE ' + EscapedTableName + ' ENABLE KEYS;' + #13#10;
            SQL := SQL + 'UNLOCK TABLES;' + #13#10;
          end;
          if (Session.Lib.LibraryType <> ltHTTP) then
            if (Session.ErrorCode <> 0) then
              SQL := SQL + 'ROLLBACK;' + #13#10
            else
              SQL := SQL + 'COMMIT;' + #13#10;
          Session.ExecuteSQL(SQL);

          DataFileBuffer.Free();
        end;

        CloseHandle(Pipe);
      end;
    end
    else
    begin
      SQLExecuteLength := 0; InsertStmtInSQL := False;

      SetLength(EscapedFieldName, Length(Fields));
      for I := 0 to Length(Fields) - 1 do
        EscapedFieldName[I] := Session.EscapeIdentifier(Fields[I].Name);

      SetLength(SQLValues, Length(Fields));
      while ((Success = daSuccess) and GetValues(Item, SQLValues)) do
      begin
        Values := ''; WhereClausel := '';
        for I := 0 to Length(Fields) - 1 do
          if (StmtType <> stUpdate) then
          begin
            if (Values <> '') then Values := Values + ',';
            Values := Values + Fields[I].EscapeValue(SQLValues[I]);
          end
          else if (not Fields[I].InPrimaryKey) then
          begin
            if (Values <> '') then Values := Values + ',';
            Values := Values + EscapedFieldName[I] + '=' + Fields[I].EscapeValue(SQLValues[I]);
          end
          else
          begin
            if (WhereClausel <> '') then WhereClausel := WhereClausel + ' AND ';
            WhereClausel := WhereClausel + EscapedFieldName[I] + '=' + Fields[I].EscapeValue(SQLValues[I]);
          end;

        if (StmtType = stUpdate) then
        begin
          if (InsertStmtInSQL) then
            SQL := SQL + ';' + #13#10;
          SQL := SQL + 'UPDATE ' + EscapedTableName + ' SET ' + Values + ' WHERE ' + WhereClausel + ';' + #13#10;
          InsertStmtInSQL := False;
        end
        else if (not InsertStmtInSQL) then
        begin
          if (StmtType = stReplace) then
            SQL := SQL + 'REPLACE INTO ' + EscapedTableName
          else
            SQL := SQL + 'INSERT INTO ' + EscapedTableName;
          if (EscapedFieldNames <> '') then
            SQL := SQL + ' (' + EscapedFieldNames + ')';
          SQL := SQL + ' VALUES (' + Values + ')';
          InsertStmtInSQL := True;
        end
        else
          SQL := SQL + ',(' + Values + ')';

        if ((StmtType = stUpdate) and not Session.MultiStatements or (Length(SQL) - SQLExecuteLength >= SQLPacketSize)) then
        begin
          if (InsertStmtInSQL) then
          begin
            SQL := SQL + ';' + #13#10;
            InsertStmtInSQL := False;
          end;

          if (SQLExecuteLength > 0) then
          begin
            SQLExecuted.WaitFor(INFINITE);
            Delete(SQL, 1, Session.ExecutedSQLLength);
            SQLExecuteLength := 0;
            if (Session.ErrorCode <> 0) then
              DoError(DatabaseError(Session), Item, True, SQL);
          end;

          if (SQL <> '') then
          begin
            Session.SendSQL(SQL, SQLExecuted);
            SQLExecuteLength := Length(SQL);
          end;
        end;

        Inc(Item.RecordsDone);
        if (Item.RecordsDone mod 100 = 0) then DoUpdateGUI();

        if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
        begin
          if (SQL <> '') then
            Session.Terminate();
          Success := daAbort;
        end;
      end;
      SetLength(SQLValues, 0);

      if ((Success = daSuccess) and (SQLExecuteLength > 0)) then
      begin
        SQLExecuted.WaitFor(INFINITE);
        Delete(SQL, 1, Session.ExecutedSQLLength);
        if (Session.ErrorCode <> 0) then
          DoError(DatabaseError(Session), Item, False, SQL);
      end;

      if (InsertStmtInSQL) then
        SQL := SQL + ';' + #13#10;
      if (Structure) then
      begin
        if ((Session.ServerVersion >= 40000) and (Table is TSBaseTable) and TSBaseTable(Table).Engine.IsMyISAM) then
          SQL := SQL + 'ALTER TABLE ' + EscapedTableName + ' ENABLE KEYS;' + #13#10;
        SQL := SQL + 'UNLOCK TABLES;' + #13#10;
      end;
      if (Session.Lib.LibraryType <> ltHTTP) then
        SQL := SQL + 'COMMIT;' + #13#10;

      while ((Success <> daAbort) and not DoExecuteSQL(Item, SQL)) do
        DoError(DatabaseError(Session), Item, True, SQL);
    end;

    SQLExecuted.Free();
  end;

  AfterExecuteData(Item);
end;

procedure TTImport.ExecuteStructure(const Item: TItem);
begin
end;

function TTImport.GetValues(const Item: TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean;
begin
  Result := False;
end;

function TTImport.GetValues(const Item: TItem; var Values: TSQLStrings): Boolean;
begin
  Result := False;
end;

procedure TTImport.Open();
begin
end;

{ TTImportFile ****************************************************************}

procedure TTImportFile.Close();
begin
  if (Handle <> INVALID_HANDLE_VALUE) then
  begin
    CloseHandle(Handle);
    Handle := INVALID_HANDLE_VALUE;
  end;

  if (Assigned(FileBuffer.Mem)) then
    VirtualFree(FileBuffer.Mem, FileBuffer.Size, MEM_RELEASE);
  FileBuffer.Index := 0;
  FileBuffer.Size := 0;

  FileContent.Str := '';
  FileContent.Index := 1;
end;

constructor TTImportFile.Create(const AFilename: TFileName; const ACodePage: Cardinal; const ASession: TSSession; const ADatabase: TSDatabase);
begin
  inherited Create(ASession, ADatabase);

  FFilename := AFilename;
  FCodePage := ACodePage;

  FilePos := 0;
  FileBuffer.Mem := nil;
  FileBuffer.Index := BytesPerSector;
  FileBuffer.Size := 0;
  FileContent.Str := '';
  FileContent.Index := 1;
  FFileSize := 0;

  Handle := INVALID_HANDLE_VALUE;
end;

procedure TTImportFile.DoUpdateGUI();
begin
  CriticalSection.Enter();

  ProgressInfos.TablesDone := -1;
  ProgressInfos.TablesSum := -1;
  ProgressInfos.RecordsDone := FilePos;
  ProgressInfos.RecordsSum := FileSize;
  ProgressInfos.TimeDone := 0;
  ProgressInfos.TimeSum := 0;

  ProgressInfos.TimeDone := Now() - StartTime;

  if ((ProgressInfos.RecordsDone = 0) or (ProgressInfos.RecordsSum = 0)) then
  begin
    ProgressInfos.Progress := 0;
    ProgressInfos.TimeSum := 0;
  end
  else if (ProgressInfos.RecordsDone < ProgressInfos.RecordsSum) then
  begin
    ProgressInfos.Progress := Round(ProgressInfos.RecordsDone / ProgressInfos.RecordsSum * 100);
    ProgressInfos.TimeSum := ProgressInfos.TimeDone / ProgressInfos.RecordsDone * ProgressInfos.RecordsSum;
  end
  else
  begin
    ProgressInfos.Progress := 100;
    ProgressInfos.TimeSum := ProgressInfos.TimeDone;
  end;

  CriticalSection.Leave();

  if (Assigned(OnUpdate)) then
    OnUpdate(ProgressInfos);
end;

function TTImportFile.DoOpenFile(const Filename: TFileName; out Handle: THandle; out Error: TTool.TError): Boolean;
var
  NumberofFreeClusters: DWord;
  SectorsPerCluser: DWord;
  TotalNumberOfClusters: DWord;
begin
  Result := True;

  try
    Handle := CreateFile(PChar(Filename),
                         GENERIC_READ,
                         FILE_SHARE_READ,
                         nil,
                         OPEN_EXISTING, FILE_FLAG_NO_BUFFERING, 0);

    if (Handle = INVALID_HANDLE_VALUE) then
      DoError(SysError(), nil, False)
    else
    begin
      FFileSize := GetFileSize(Handle, nil);
      if (FFileSize = 0) then
        FileBuffer.Mem := nil
      else
      begin
        if (not GetDiskFreeSpace(PChar(ExtractFileDrive(Filename)), SectorsPerCluser, BytesPerSector, NumberofFreeClusters, TotalNumberOfClusters)) then
          RaiseLastOSError();
        FileBuffer.Size := BytesPerSector + Min(FFileSize, FilePacketSize);
        Inc(FileBuffer.Size, BytesPerSector - FileBuffer.Size mod BytesPerSector);
        FileBuffer.Mem := VirtualAlloc(nil, FileBuffer.Size, MEM_COMMIT, PAGE_READWRITE);
        FileBuffer.Index := BytesPerSector;

        ReadContent();
      end;
    end;
  except
    Error := SysError();

    Result := False;
  end;
end;

function TTImportFile.ReadContent(const NewFilePos: TLargeInteger = -1): Boolean;
var
  DistanceToMove: TLargeInteger;
  Error: TTool.TError;
  Index: Integer;
  Len: Integer;
  ReadSize: DWord;
  UTF8Bytes: Byte;
begin
  // The file will be read without buffering in Windows OS. Because of this,
  // we have to read complete sectors...

  if ((Success = daSuccess) and (NewFilePos >= 0)) then
  begin
    FileContent.Str := '';

    DistanceToMove := NewFilePos - NewFilePos mod BytesPerSector;
    if ((SetFilePointer(Handle, LARGE_INTEGER(DistanceToMove).LowPart, @LARGE_INTEGER(DistanceToMove).HighPart, FILE_BEGIN) = INVALID_FILE_SIZE) and (GetLastError() <> 0)) then
      DoError(SysError(), nil, False);
    FileBuffer.Index := BytesPerSector + NewFilePos mod BytesPerSector;

    FilePos := NewFilePos - NewFilePos mod BytesPerSector;
  end
  else
  begin
    if (FileContent.Index > 1) then
      Delete(FileContent.Str, 1, FileContent.Index - 1);
  end;
  FileContent.Index := 1;

  if ((Success = daSuccess) and ReadFile(Handle, FileBuffer.Mem[BytesPerSector], FileBuffer.Size - BytesPerSector, ReadSize, nil) and (ReadSize > 0)) then
  begin
    if (FilePos = 0) then
    begin
      if (CompareMem(@FileBuffer.Mem[FileBuffer.Index + 0], BOM_UTF8, Length(BOM_UTF8))) then
      begin
        BOMLength := Length(BOM_UTF8);
        FCodePage := CP_UTF8;
      end
      else if (CompareMem(@FileBuffer.Mem[FileBuffer.Index + 0], BOM_UNICODE_LE, Length(BOM_UNICODE_LE))) then
      begin
        BOMLength := Length(BOM_UNICODE_LE);
        FCodePage := CP_UNICODE;
      end
      else
        BOMLength := 0;

      FilePos := BOMLength;
      Inc(FileBuffer.Index, FilePos);
    end;
    Inc(FilePos, ReadSize);

    case (CodePage) of
      CP_UNICODE:
        begin
          Index := 1 + Length(FileContent.Str);
          Len := Integer(ReadSize - (FileBuffer.Index - BytesPerSector));
          SetLength(FileContent.Str, Length(FileContent.Str) + Len div SizeOf(Char));
          MoveMemory(@FileContent.Str[Index], @FileBuffer.Mem[FileBuffer.Index], Len);
          FileBuffer.Index := BytesPerSector;
        end;
      else
        begin
          // UTF-8 coded bytes has to be separated well for the
          // MultiByteToWideChar function.
          UTF8Bytes := 0;
          if ((CodePage = CP_UTF8) and (Byte(FileBuffer.Mem[BytesPerSector + ReadSize - UTF8Bytes - 1]) and $80 <> 0)) then
            repeat
              Inc(UTF8Bytes);
            until ((BytesPerSector + ReadSize - UTF8Bytes - 1 = 0)
              or (Byte(FileBuffer.Mem[BytesPerSector + ReadSize - UTF8Bytes]) and $C0 = 0)
              or (Byte(FileBuffer.Mem[BytesPerSector + ReadSize - UTF8Bytes]) and $C0 <> $80));

          if (BytesPerSector + ReadSize - FileBuffer.Index > 0) then
          begin
            try
              Len := AnsiCharToWideChar(CodePage, @FileBuffer.Mem[FileBuffer.Index], BytesPerSector + ReadSize - UTF8Bytes - FileBuffer.Index, nil, 0);
            except
              Len := 0;
              Error.ErrorType := TE_File;
              Error.ErrorCode := GetLastError();
              Error.ErrorMessage := Preferences.LoadStr(895, Filename);
              DoError(Error, nil, False);
            end;
            if (Len > 0) then
            begin
              SetLength(FileContent.Str, Length(FileContent.Str) + Len);
              AnsiCharToWideChar(CodePage, @FileBuffer.Mem[FileBuffer.Index], BytesPerSector + ReadSize - UTF8Bytes - FileBuffer.Index, @FileContent.Str[Length(FileContent.Str) - Len + 1], Len)
            end;
          end;

          if (UTF8Bytes > 0) then
            MoveMemory(@FileBuffer.Mem[BytesPerSector - UTF8Bytes], @FileBuffer.Mem[BytesPerSector + ReadSize - UTF8Bytes], UTF8Bytes);

          FileBuffer.Index := BytesPerSector - UTF8Bytes;
        end;
    end;
  end;

  Result := (Success = daSuccess) and (ReadSize > 0);
end;

procedure TTImportFile.Open();
var
  Error: TTool.TError;
begin
  FilePos := 0;

  while ((Success <> daAbort) and not DoOpenFile(FFilename, Handle, Error)) do
    DoError(Error, nil, True);
end;

{ TTImportSQL *************************************************************}

constructor TTImportSQL.Create(const AFilename: TFileName; const ACodePage: Cardinal; const ASession: TSSession; const ADatabase: TSDatabase);
begin
  inherited;

  Items.Add(TTImport.TItem.Create(Items));

  FSetNamesApplied := False;
  Text := nil
end;

procedure TTImportSQL.Execute();
var
  CLStmt: TSQLCLStmt;
  CompleteStmt: Boolean;
  Eof: Boolean;
  Index: Integer;
  Len: Integer;
  SetNames: Boolean;
  SQL: string;
  SQLFilePos: TLargeInteger;
begin
  {$IFDEF EurekaLog}
  try
  {$ENDIF}

  if (not Assigned(Text)) then
    BeforeExecute();

  Open();

  if (Assigned(Text)) then
    Text^ := ''
  else if ((Success = daSuccess) and Assigned(Database) and (Session.DatabaseName <> Database.Name)) then
  begin
    SQL := Database.SQLUse();
    while ((Success <> daAbort) and not DoExecuteSQL(TTImport.TItem(Items[0]), SQL)) do
      DoError(DatabaseError(Session), Items[0], True, SQL);
  end;

  Index := 1; Eof := False; SQLFilePos := BOMLength;
  while ((Success = daSuccess) and (not Eof or (Index <= Length(FileContent.Str)))) do
  begin
    repeat
      if ((Index - 1) = Length(FileContent.Str)) then
      begin
        Len := 0;
        CompleteStmt := False;
      end
      else
        Len := SQLStmtLength(PChar(@FileContent.Str[Index]), Length(FileContent.Str) - (Index - 1), @CompleteStmt);
      if (not CompleteStmt) then
      begin
        Eof := not ReadContent();
        if (not Eof) then
          Len := 0
        else
          Len := Length(FileContent.Str) - (Index - 1);
      end;
    until ((Len > 0) or Eof);

    if (Len > 0) then
      case (CodePage) of
        CP_UNICODE: Inc(SQLFilePos, Len * SizeOf(Char));
        else Inc(SQLFilePos, WideCharToAnsiChar(CodePage, PChar(@FileContent.Str[Index]), Len, nil, 0));
      end;

    SetNames := not EOF
      and SQLParseCLStmt(CLStmt, @FileContent.Str[Index], Length(FileContent.Str), Session.ServerVersion)
      and (CLStmt.CommandType in [ctSetNames, ctSetCharacterSet]);

    if ((Index > 1) and (SetNames or (Index - 1 + Len >= SQLPacketSize))) then
    begin
      if (Assigned(Text)) then
        Text^ := Text^ + Copy(FileContent.Str, 1, Index - 1)
      else
      begin
        SQL := Copy(FileContent.Str, 1, Index - 1);
        while ((Success <> daAbort) and not DoExecuteSQL(TTImport.TItem(Items[0]), SQL)) do
          DoError(DatabaseError(Session), Items[0], True, SQL);
      end;
      Delete(FileContent.Str, 1, Index - 1); Index := 1;

      DoUpdateGUI();
    end;

    if (Success = daSuccess) then
    begin
      if (SetNames) then
      begin
        FSetNamesApplied := True;

        FCodePage := Session.CharsetToCodePage(CLStmt.ObjectName);

        ReadContent(SQLFilePos); // Clear FileContent
      end
      else
        Inc(Index, Len);
    end;

    if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
      Success := daAbort;
  end;

  if (Success = daSuccess) then
    if (Assigned(Text)) then
      Text^ := Text^ + FileContent.Str
    else
    begin
      SQL := FileContent.Str;
      while ((Success <> daAbort) and not DoExecuteSQL(TTImport.TItem(Items[0]), SQL)) do
        DoError(DatabaseError(Session), Items[0], True, SQL);
    end;

  if (not Assigned(Text)) then
    AfterExecute();

  {$IFDEF EurekaLog}
  except
    StandardEurekaNotify(GetLastExceptionObject(), GetLastExceptionAddress());
  end;
  {$ENDIF}
end;

{ TTImportText ****************************************************************}

procedure TTImportText.AfterExecuteData(const Item: TTImport.TItem);
begin
  SetLength(CSVValues, 0);

  inherited;
end;

procedure TTImportText.BeforeExecuteData(const Item: TTImport.TItem);
var
  I: Integer;
  J: Integer;
begin
  inherited;

  SetLength(CSVColumns, Length(SourceFields));
  for I := 0 to Length(SourceFields) - 1 do
  begin
    CSVColumns[I] := -1;
    for J := 0 to HeadlineNameCount - 1 do
      if (SourceFields[I].Name = HeadlineNames[J]) then
        CSVColumns[I] := J;
  end;
end;

procedure TTImportText.Close();
begin
  inherited;

  SetLength(FileFields, 0);
end;

constructor TTImportText.Create(const AFilename: TFileName; const ACodePage: Cardinal; const ASession: TSSession; const ADatabase: TSDatabase);
begin
  inherited Create(AFilename, ACodePage, ASession, ADatabase);

  SetLength(CSVValues, 0);
  Data := True;
  Delimiter := ',';
  Quoter := '"';
  CSVUnquoteMemSize := NET_BUFFER_LENGTH;
  GetMem(CSVUnquoteMem, CSVUnquoteMemSize);
end;

destructor TTImportText.Destroy();
begin
  SetLength(Fields, 0);
  FreeMem(CSVUnquoteMem);

  inherited;
end;

procedure TTImportText.ExecuteStructure(const Item: TTImport.TItem);
var
  I: Integer;
  NewField: TSBaseTableField;
  NewTable: TSBaseTable;
begin
  NewTable := TSBaseTable.Create(Database.Tables);

  for I := 0 to Length(FileFields) - 1 do
  begin
    NewField := TSBaseTableField.Create(NewTable.Fields);

    NewField.Name := Session.ApplyIdentifierName(HeadlineNames[I]);

    if (SQL_INTEGER in FileFields[I].FieldTypes) then
      NewField.FieldType := mfInt
    else if (SQL_FLOAT in FileFields[I].FieldTypes) then
      NewField.FieldType := mfFloat
    else if (SQL_DATE in FileFields[I].FieldTypes) then
      NewField.FieldType := mfDate
    else
      NewField.FieldType := mfText;

    if (I > 0) then
      NewField.FieldBefore := NewTable.Fields[NewTable.Fields.Count - 1];

    NewTable.Fields.AddField(NewField);
    NewField.Free();
  end;

  NewTable.Name := Session.ApplyIdentifierName(Item.TableName);

  Session.BeginSynchron();
  while ((Success <> daAbort) and not Database.AddTable(NewTable)) do
    DoError(DatabaseError(Session), Item, True);
  Session.EndSynchron();

  NewTable.Free();

  if (Success = daSuccess) then
  begin
    NewTable := Database.BaseTableByName(Item.TableName);
    while ((Success <> daAbort) and not NewTable.Update()) do
      DoError(DatabaseError(Session), Item, True);

    SetLength(Fields, NewTable.Fields.Count);
    for I := 0 to NewTable.Fields.Count - 1 do
      Fields[I] := NewTable.Fields[I];

    SetLength(SourceFields, NewTable.Fields.Count);
    for I := 0 to HeadlineNameCount - 1 do
      SourceFields[I].Name := HeadlineNames[I];
  end;
end;

function TTImportText.GetHeadlineNameCount(): Integer;
begin
  Result := Length(FileFields);
end;

function TTImportText.GetHeadlineName(Index: Integer): string;
begin
  Result := FileFields[Index].Name;
end;

function TTImportText.GetPreviewValues(var Values: TSQLStrings): Boolean;
var
  Eof: Boolean;
  I: Integer;
  RecordComplete: Boolean;
begin
  RecordComplete := False; Eof := False;
  while ((Success = daSuccess) and not RecordComplete and not Eof) do
  begin
    RecordComplete := CSVSplitValues(FileContent.Str, FileContent.Index, Delimiter, Quoter, CSVValues);
    if (not RecordComplete) then
      Eof := not ReadContent();
  end;

  Result := (Success = daSuccess) and RecordComplete;
  if (Result) then
  begin
    SetLength(Values, Length(CSVValues));
    for I := 0 to Length(CSVValues) - 1 do
      if (CSVValues[I].Length = 0) then
        if (not Preferences.GridNullText) then
          Values[I] := ''
        else
          Values[I] := '<NULL>'
      else
        Values[I] := CSVUnescape(CSVValues[I].Text, CSVValues[I].Length, Quoter);
  end;
end;

function TTImportText.GetValues(const Item: TTImport.TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean;
var
  EOF: Boolean;
  I: Integer;
  Len: Integer;
  OldFileContentIndex: Integer;
  RecordComplete: Boolean;
begin
  RecordComplete := False; EOF := False; OldFileContentIndex := FileContent.Index;
  while ((Success = daSuccess) and not RecordComplete and not EOF) do
  begin
    RecordComplete := CSVSplitValues(FileContent.Str, FileContent.Index, Delimiter, Quoter, CSVValues);
    if (not RecordComplete) then
    begin
      FileContent.Index := OldFileContentIndex;
      EOF := not ReadContent();
    end;
  end;

  Result := RecordComplete;
  if (Result) then
    for I := 0 to Length(Fields) - 1 do
    begin
      if (I > 0) then
        DataFileBuffer.Write(PAnsiChar(',_'), 1); // Two characters are needed to instruct the compiler to give a pointer - but the first character should be placed in the file only
      if ((I >= Length(CSVValues)) or (CSVValues[CSVColumns[I]].Length = 0)) then
        DataFileBuffer.Write(PAnsiChar('NULL'), 4)
      else
      begin
        if (not Assigned(CSVValues[CSVColumns[I]].Text) or (CSVValues[CSVColumns[I]].Length = 0)) then
          Len := 0
        else
        begin
          if (CSVValues[CSVColumns[I]].Length > CSVUnquoteMemSize) then
          begin
            CSVUnquoteMemSize := CSVUnquoteMemSize + 2 * (CSVValues[CSVColumns[I]].Length - CSVUnquoteMemSize);
            ReallocMem(CSVUnquoteMem, CSVUnquoteMemSize);
          end;
          Len := CSVUnquote(CSVValues[CSVColumns[I]].Text, CSVValues[CSVColumns[I]].Length, CSVUnquoteMem, CSVUnquoteMemSize, Quoter);
        end;

        if (Fields[I].FieldType in BinaryFieldTypes) then
          DataFileBuffer.WriteBinary(CSVUnquoteMem, Len)
        else if (Fields[I].FieldType in TextFieldTypes) then
          DataFileBuffer.WriteText(CSVUnquoteMem, Len)
        else
          DataFileBuffer.WriteData(CSVUnquoteMem, Len, not (Fields[I].FieldType in NotQuotedFieldTypes));
      end;
    end;
end;

function TTImportText.GetValues(const Item: TTImport.TItem; var Values: TSQLStrings): Boolean;
var
  Eof: Boolean;
  I: Integer;
  RecordComplete: Boolean;
begin
  RecordComplete := False; Eof := False;
  while ((Success = daSuccess) and not RecordComplete and not Eof) do
  begin
    RecordComplete := CSVSplitValues(FileContent.Str, FileContent.Index, Delimiter, Quoter, CSVValues);
    if (not RecordComplete) then
      Eof := not ReadContent();
  end;

  Result := RecordComplete;
  if (Result) then
    for I := 0 to Length(Fields) - 1 do
      if ((I >= Length(CSVValues)) or (CSVValues[CSVColumns[I]].Length = 0)) then
        Values[I] := 'NULL'
      else
        Values[I] := CSVUnescape(CSVValues[CSVColumns[I]].Text, CSVValues[CSVColumns[I]].Length, Quoter);
end;

procedure TTImportText.Open();
var
  DT: TDateTime;
  EOF: Boolean;
  F: Double;
  FirstRecordFilePos: Integer;
  I: Integer;
  Int: Integer;
  OldSuccess: TDataAction;
  OldFileContentIndex: Integer;
  RecNo: Integer;
  RecordComplete: Boolean;
  Value: string;
begin
  inherited;

  OldSuccess := Success; OldFileContentIndex := FileContent.Index;
  FirstRecordFilePos := BOMLength;

  RecordComplete := False; Eof := False;
  while (not RecordComplete and not Eof) do
  begin
    RecordComplete := CSVSplitValues(FileContent.Str, FileContent.Index, Delimiter, Quoter, CSVValues);
    if (not RecordComplete) then
      Eof := not ReadContent();
  end;

  if (UseHeadline) then
  begin
    if (FileContent.Str = '') then
      FirstRecordFilePos := SizeOf(Char)
    else
      case (CodePage) of
        CP_Unicode: FirstRecordFilePos := BOMLength + (FileContent.Index - 1) * SizeOf(Char);
        else FirstRecordFilePos := BOMLength + WideCharToAnsiChar(CodePage, PChar(@FileContent.Str[OldFileContentIndex]), FileContent.Index - OldFileContentIndex, nil, 0);
      end;
    SetLength(FileFields, Length(CSVValues));
    for I := 0 to Length(FileFields) - 1 do
      FileFields[I].Name := CSVUnescape(CSVValues[I].Text, CSVValues[I].Length, Quoter);
  end
  else
  begin
    SetLength(FileFields, Length(CSVValues));
    for I := 0 to Length(FileFields) - 1 do
      FileFields[I].Name := 'Field_' + IntToStr(I);
  end;

  for I := 0 to Length(FileFields) - 1 do
    FileFields[I].FieldTypes := [SQL_INTEGER, SQL_FLOAT, SQL_DATE, Byte(SQL_LONGVARCHAR)];

  RecNo := 0; EOF := False;
  while ((RecNo < 20) and not EOF and RecordComplete) do
  begin
    RecordComplete := (RecNo = 0) and not UseHeadline;
    while (not RecordComplete and not Eof) do
    begin
      RecordComplete := CSVSplitValues(FileContent.Str, FileContent.Index, Delimiter, Quoter, CSVValues);
      if (not RecordComplete) then
        Eof := not ReadContent();
    end;

    if (RecordComplete and (Length(CSVValues) = Length(FileFields))) then
    begin
      for I := 0 to Length(CSVValues) - 1 do
        if (CSVValues[I].Length > 0) then
        begin
          Value := CSVUnescape(CSVValues[I].Text, CSVValues[I].Length, Quoter);
          if ((SQL_INTEGER in FileFields[I].FieldTypes) and not TryStrToInt(Value, Int)) then
            Exclude(FileFields[I].FieldTypes, SQL_INTEGER);
          if ((SQL_FLOAT in FileFields[I].FieldTypes) and not TryStrToFloat(Value, F, Session.FormatSettings)) then
            Exclude(FileFields[I].FieldTypes, SQL_FLOAT);
          if ((SQL_DATE in FileFields[I].FieldTypes) and (not TryStrToDate(Value, DT, Session.FormatSettings) or (DT < EncodeDate(1900, 1, 1)))) then
            Exclude(FileFields[I].FieldTypes, SQL_DATE);
        end;

      Inc(RecNo);
    end;
  end;

  Success := OldSuccess; ReadContent(FirstRecordFilePos);
end;

procedure TTImportText.Reset();
begin
  Close();
end;

{ TTImportBaseODBC ************************************************************}

function SQLDataTypeToMySQLType(const SQLType: SQLSMALLINT; const Size: Integer; const FieldName: string): TMySQLFieldType;
begin
  case (SQLType) of
    SQL_CHAR: Result := mfChar;
    SQL_VARCHAR: Result := mfVarChar;
    SQL_LONGVARCHAR: Result := mfText;
    SQL_WCHAR: Result := mfChar;
    SQL_WVARCHAR: Result := mfVarChar;
    SQL_WLONGVARCHAR: Result := mfText;
    SQL_DECIMAL: Result := mfDecimal;
    SQL_NUMERIC: Result := mfDecimal;
    SQL_BIT: Result := mfBit;
    SQL_TINYINT: Result := mfTinyInt;
    SQL_SMALLINT: Result := mfSmallInt;
    SQL_INTEGER: Result := mfInt;
    SQL_BIGINT: Result := mfBigInt;
    SQL_REAL: Result := mfFloat;
    SQL_FLOAT: Result := mfFloat;
    SQL_DOUBLE: Result := mfDouble;
    SQL_BINARY: Result := mfBinary;
    SQL_VARBINARY: Result := mfVarBinary;
    SQL_LONGVARBINARY: Result := mfBlob;
    SQL_DATETIME: Result := mfDateTime;
    SQL_TYPE_DATE: Result := mfDate;
    SQL_TYPE_TIME: Result := mfTime;
    SQL_TYPE_TIMESTAMP: Result := mfDateTime;
    SQL_TIMESTAMP: Result := mfTimestamp;
    SQL_GUID: Result := mfChar;
    else raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [FieldName, SQLType]);
  end;
end;

procedure TTImportBaseODBC.AfterExecuteData(const Item: TTImport.TItem);
var
  I: Integer;
begin
  Item.RecordsSum := Item.RecordsDone;

  for I := 0 to Length(ColumnDesc) - 1 do
    FreeMem(ColumnDesc[I].ColumnName);
  SetLength(ColumnDesc, 0);

  if (Assigned(ODBCData)) then
    FreeMem(ODBCData);
  if (Stmt <> SQL_NULL_HANDLE) then
    SQLFreeHandle(SQL_HANDLE_STMT, Stmt);
end;

procedure TTImportBaseODBC.BeforeExecute();
var
  cbRecordsSum: SQLINTEGER;
  Handle: SQLHSTMT;
  I: Integer;
  RecordsSum: array [0..20] of SQLTCHAR;
  SQL: string;
begin
  inherited;

  for I := 0 to Items.Count - 1 do
    if ((Success <> daAbort) and Data) then
    begin
      Success := daSuccess;

      if (SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, FHandle, @Handle))) then
      begin
        SQL := 'SELECT COUNT(*) FROM "' + TTImport.TItem(Items[I]).SourceTableName + '"';
        if (SQL_SUCCEEDED(SQLExecDirect(Handle, PSQLTCHAR(SQL), SQL_NTS))
          and SQL_SUCCEEDED(SQLFetch(Handle))
          and SQL_SUCCEEDED(SQLGetData(Handle, 1, SQL_C_WCHAR, @RecordsSum, SizeOf(RecordsSum) - 1, @cbRecordsSum))) then
            Items[I].RecordsSum := StrToInt(PChar(@RecordsSum));

        SQLFreeHandle(SQL_HANDLE_STMT, Handle);
      end;
    end;
end;

procedure TTImportBaseODBC.BeforeExecuteData(const Item: TTImport.TItem);
var
  cbColumnName: SQLSMALLINT;
  ColumnNums: SQLSMALLINT;
  Error: TTool.TError;
  I: Integer;
  SQL: string;
  Unsigned: SQLINTEGER;
begin
  inherited;

  if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, FHandle, @Stmt))) then
  begin
    Error := ODBCError(SQL_HANDLE_DBC, FHandle);
    DoError(Error, Item, False);
    Stmt := SQL_NULL_HANDLE;
    ODBCData := nil;
    SetLength(ColumnDesc, 0);
  end
  else
  begin
    GetMem(ODBCData, ODBCDataSize);

    SQL := '';
    if (not Structure and (Length(SourceFields) > 1)) then
      for I := 0 to Length(SourceFields) - 1 do
      begin
        if (I > 0) then SQL := SQL + ',';
        SQL := SQL + '"' + SourceFields[I].Name + '"';
      end
    else
      SQL := '*';
    SQL := 'SELECT ' + SQL + ' FROM "' + Item.SourceTableName + '"';

    while ((Success <> daAbort) and not SQL_SUCCEEDED(SQLExecDirect(Stmt, PSQLTCHAR(SQL), SQL_NTS))) do
      DoError(ODBCError(SQL_HANDLE_STMT, Stmt), Item, True);

    if (Success = daSuccess) then
    begin
      ODBCException(Stmt, SQLNumResultCols(Stmt, @ColumnNums));

      SetLength(ColumnDesc, ColumnNums);
      if (Success = daSuccess) then
        for I := 0 to Length(ColumnDesc) - 1 do
        begin
          ODBCException(Stmt, SQLDescribeCol(Stmt, I + 1, nil, 0, @cbColumnName, nil, nil, nil, nil));
          GetMem(ColumnDesc[I].ColumnName, (cbColumnName + 1) * SizeOf(SQLTCHAR));

          ODBCException(Stmt, SQLDescribeCol(Stmt, I + 1, ColumnDesc[I].ColumnName, cbColumnName, nil, @ColumnDesc[I].SQLDataType, @ColumnDesc[I].MaxDataSize, @ColumnDesc[I].DecimalDigits, @ColumnDesc[I].Nullable));
          case (ColumnDesc[I].SQLDataType) of
            SQL_TINYINT,
            SQL_SMALLINT,
            SQL_INTEGER,
            SQL_BIGINT:
              begin
                ODBCException(Stmt, SQLColAttribute(Stmt, I + 1, SQL_DESC_UNSIGNED, nil, 0, nil, @Unsigned));
                if (Unsigned = SQL_TRUE) then
                  case (ColumnDesc[I].SQLDataType) of
                    SQL_TINYINT: ColumnDesc[I].SQL_C_TYPE := SQL_C_UTINYINT;
                    SQL_SMALLINT: ColumnDesc[I].SQL_C_TYPE := SQL_C_USHORT;
                    SQL_INTEGER: ColumnDesc[I].SQL_C_TYPE := SQL_C_ULONG;
                    SQL_BIGINT: ColumnDesc[I].SQL_C_TYPE := SQL_C_UBIGINT;
                  end
                else
                  case (ColumnDesc[I].SQLDataType) of
                    SQL_TINYINT: ColumnDesc[I].SQL_C_TYPE := SQL_C_STINYINT;
                    SQL_SMALLINT: ColumnDesc[I].SQL_C_TYPE := SQL_C_SSHORT;
                    SQL_INTEGER: ColumnDesc[I].SQL_C_TYPE := SQL_C_SLONG;
                    SQL_BIGINT: ColumnDesc[I].SQL_C_TYPE := SQL_C_SBIGINT;
                  end;
              end
          end;
        end;
    end;
  end;
end;

procedure TTImportBaseODBC.Close();
begin
  if (FHandle <> SQL_NULL_HANDLE) then
  begin
    SQLDisconnect(FHandle);
    SQLFreeHandle(SQL_HANDLE_DBC, FHandle); FHandle := SQL_NULL_HANDLE;
  end;
end;

constructor TTImportBaseODBC.Create(const ASession: TSSession; const ADatabase: TSDatabase);
begin
  inherited Create(ASession, ADatabase);

  ODBCMemSize := 256;
  GetMem(ODBCMem, ODBCMemSize);
end;

destructor TTImportBaseODBC.Destroy();
begin
  FreeMem(ODBCMem);

  inherited;
end;

procedure TTImportBaseODBC.ExecuteStructure(const Item: TTImport.TItem);
var
  AscOrDesc: array [0 .. 2 - 1] of SQLTCHAR;
  AutoUniqueValue: SQLINTEGER;
  cbAscOrDesc: SQLINTEGER;
  cbColumnDef: SQLINTEGER;
  cbColumnName: SQLINTEGER;
  cbColumnSize: SQLINTEGER;
  cbDecimalDigits: SQLINTEGER;
  cbDRIVER_ODBC_VER: SQLINTEGER;
  cbIndexName: SQLINTEGER;
  cbIndexType: SQLINTEGER;
  cbNonUnique: SQLINTEGER;
  cbNullable: SQLINTEGER;
  cbOrdinalPosition: SQLINTEGER;
  cbRemarks: SQLINTEGER;
  cbSQLDataType: SQLINTEGER;
  cbSQLDataType2: SQLINTEGER;
  ColumnDef: array [0 .. STR_LEN] of SQLTCHAR;
  ColumnName: array [0 .. STR_LEN] of SQLTCHAR;
  ColumnNumber: SQLINTEGER;
  ColumnSize: SQLINTEGER;
  DecimalDigits: SQLSMALLINT;
  DRIVER_ODBC_VER: array [0 .. STR_LEN] of SQLTCHAR;
  DriverVer: Integer;
  F: Single;
  Found: Boolean;
  I: Integer;
  Key: TSKey;
  IndexName: array [0 .. STR_LEN] of SQLTCHAR;
  IndexType: SQLSMALLINT;
  J: Integer;
  Len: SQLINTEGER;
  NewKeyColumn: TSKeyColumn;
  NewField: TSBaseTableField;
  NewTable: TSBaseTable;
  NonUnique: SQLSMALLINT;
  Nullable: SQLSMALLINT;
  OrdinalPosition: SQLSMALLINT;
  Remarks: array [0 .. 256 - 1] of SQLTCHAR;
  S: string;
  SQLDataType: SQLSMALLINT;
  SQLDataType2: SQLSMALLINT;
  Stmt: SQLHSTMT;
  Table: TSBaseTable;
  Unsigned: SQLINTEGER;
begin
  SetLength(SourceFields, 0);

  NewTable := TSBaseTable.Create(Database.Tables);
  NewTable.DefaultCharset := Charset;
  NewTable.Collation := Collation;
  NewTable.Engine := Session.EngineByName(Engine);
  NewTable.RowType := RowType;

  if (SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, FHandle, @Stmt))) then
  begin
    if ((Success <> daAbort) and (SQLColumns(Stmt, nil, 0, nil, 0, PSQLTCHAR(Item.SourceTableName), SQL_NTS, nil, 0) <> SQL_SUCCESS)) then
      DoError(ODBCError(SQL_HANDLE_STMT, Stmt), Item, False);

    if (not SQL_SUCCEEDED(SQLGetInfo(Handle, SQL_DRIVER_ODBC_VER, @DRIVER_ODBC_VER, SizeOf(DRIVER_ODBC_VER), @cbDRIVER_ODBC_VER))) then
    begin
      DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False);
      DriverVer := 0;
    end
    else
    begin
      SetString(S, PChar(@DRIVER_ODBC_VER), cbDRIVER_ODBC_VER div SizeOf(DRIVER_ODBC_VER[0]));
      if (not TryStrToFloat(S, F)) then
        DriverVer := 0
      else
        DriverVer := Trunc(F);
    end;

    if (Success = daSuccess) then
    begin
      ODBCException(Stmt, SQLBindCol(Stmt, 4, SQL_C_WCHAR, @ColumnName, SizeOf(ColumnName), @cbColumnName));
      ODBCException(Stmt, SQLBindCol(Stmt, 5, SQL_C_SSHORT, @SQLDataType, SizeOf(SQLDataType), @cbSQLDataType));
      ODBCException(Stmt, SQLBindCol(Stmt, 7, SQL_C_SLONG, @ColumnSize, SizeOf(ColumnSize), @cbColumnSize));
      ODBCException(Stmt, SQLBindCol(Stmt, 9, SQL_C_SSHORT, @DecimalDigits, SizeOf(DecimalDigits), @cbDecimalDigits));
      ODBCException(Stmt, SQLBindCol(Stmt, 11, SQL_C_SSHORT, @Nullable, SizeOf(Nullable), @cbNullable));
      if (not SQL_SUCCEEDED(SQLBindCol(Stmt, 12, SQL_C_WCHAR, @Remarks, SizeOf(Remarks), @cbRemarks))) then
        begin ZeroMemory(@Remarks, SizeOf(Remarks)); cbRemarks := 0; end;
      if (DriverVer >= 3) then
      begin
        if (not SQL_SUCCEEDED(SQLBindCol(Stmt, 13, SQL_C_WCHAR, @ColumnDef, SizeOf(ColumnDef), @cbColumnDef))) then
          begin ZeroMemory(@ColumnDef, SizeOf(ColumnDef)); cbColumnDef := 0; end;
        if (not SQL_SUCCEEDED(SQLBindCol(Stmt, 14, SQL_C_SSHORT, @SQLDataType2, SizeOf(SQLDataType2), @cbSQLDataType2))) then
          begin ZeroMemory(@SQLDataType2, SizeOf(SQLDataType2)); cbSQLDataType2 := 0; end;
      end;

      while (SQL_SUCCEEDED(ODBCException(Stmt, SQLFetch(Stmt)))) do
        if (not Assigned(NewTable.FieldByName(ColumnName))) then
        begin
          SetLength(SourceFields, Length(SourceFields) + 1);
          SourceFields[Length(SourceFields) - 1].Name := ColumnName;


          NewField := TSBaseTableField.Create(NewTable.Fields);
          NewField.Name := Session.ApplyIdentifierName(ColumnName);
          if (NewTable.Fields.Count > 0) then
            NewField.FieldBefore := NewTable.Fields[NewTable.Fields.Count - 1];
          if (SQLDataType <> SQL_UNKNOWN_TYPE) then
            NewField.FieldType := SQLDataTypeToMySQLType(SQLDataType, ColumnSize, NewField.Name)
          else if ((DriverVer >= 3) and (cbSQLDataType2 > 0)) then
            NewField.FieldType := SQLDataTypeToMySQLType(SQLDataType2, ColumnSize, NewField.Name)
          else
            raise EODBCError.CreateFMT(SUnknownFieldType + ' (%d)', [ColumnName, SQLDataType]);
          if (not (NewField.FieldType in [mfFloat, mfDouble, mfDecimal]) or (DecimalDigits > 0)) then
          begin
            NewField.Size := ColumnSize;
            NewField.Decimals := DecimalDigits;
          end;
          if ((DriverVer >= 3) and (cbColumnDef > 0)) then
          begin
            SetString(S, ColumnDef, cbColumnDef);
            while ((Length(S) > 0) and (S[Length(S)] = #0)) do
              Delete(S, Length(S), 1);
            if (SysUtils.UpperCase(S) = 'NULL') then
              NewField.Default := 'NULL'
            else if ((NewField.FieldType in [mfTinyInt, mfSmallInt, mfMediumInt, mfInt, mfBigInt]) and (SysUtils.LowerCase(S) = '(newid())')) then
              NewField.AutoIncrement := True
            else if (SysUtils.LowerCase(S) = '(getdate())') then
            begin
              NewField.FieldType := mfTimestamp;
              NewField.Default := 'CURRENT_TIMESTAMP';
            end
            else if (NewField.FieldType in NotQuotedFieldTypes) then
            begin
              S := NewField.UnescapeValue(S);
              if ((LeftStr(S, 1) = '(') and (RightStr(S, 1) = ')')) then
                S := Copy(S, 2, Length(S) - 2);
              NewField.Default := S;
            end
            else if ((LeftStr(S, 1) <> '(') or (RightStr(S, 1) <> ')')) then
              NewField.Default := NewField.EscapeValue(NewField.UnescapeValue(S));
          end;
          NewField.NullAllowed := (Nullable <> SQL_NO_NULLS) or (NewField.Default = 'NULL');
          NewField.Comment := Remarks;

          NewTable.Fields.AddField(NewField);
          FreeAndNil(NewField);
        end;
    end;

    SQLFreeHandle(SQL_HANDLE_STMT, Stmt);


    if ((Success = daSuccess) and SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, FHandle, @Stmt))) then
    begin
      if (SQL_SUCCEEDED(SQLExecDirect(Stmt, PSQLTCHAR(string('SELECT * FROM "' + Item.SourceTableName + '" WHERE 0<>0')), SQL_NTS))) then
      begin
        ColumnNumber := 1;
        while (SQL_SUCCEEDED(SQLColAttribute(Stmt, ColumnNumber, SQL_DESC_BASE_COLUMN_NAME, @ColumnName, SizeOf(ColumnName), @cbColumnName, nil))) do
        begin
          ODBCException(Stmt, SQLColAttribute(Stmt, ColumnNumber, SQL_DESC_AUTO_UNIQUE_VALUE, nil, 0, nil, @AutoUniqueValue));
          ODBCException(Stmt, SQLColAttribute(Stmt, ColumnNumber, SQL_DESC_UNSIGNED, nil, 0, nil, @Unsigned));
          NewField := NewTable.FieldByName(ColumnName);
          if (Assigned(NewField)) then
          begin
            NewField.AutoIncrement := AutoUniqueValue = SQL_TRUE;
            NewField.Unsigned := Unsigned = SQL_TRUE;
          end;

          Inc(ColumnNumber)
        end;
      end;
      SQLFreeHandle(SQL_HANDLE_STMT, Stmt);
    end;
  end;

  if ((Success = daSuccess) and SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, FHandle, @Stmt))) then
  begin
    ODBCException(Stmt, SQLStatistics(Stmt, nil, 0, nil, 0, PSQLTCHAR(Item.SourceTableName), SQL_NTS, SQL_INDEX_UNIQUE, SQL_QUICK));

    ODBCException(Stmt, SQLBindCol(Stmt, 4, SQL_C_SSHORT, @NonUnique, SizeOf(NonUnique), @cbNonUnique));
    ODBCException(Stmt, SQLBindCol(Stmt, 6, SQL_C_WCHAR, @IndexName, SizeOf(IndexName), @cbIndexName));
    ODBCException(Stmt, SQLBindCol(Stmt, 7, SQL_C_SSHORT, @IndexType, SizeOf(IndexType), @cbIndexType));
    ODBCException(Stmt, SQLBindCol(Stmt, 8, SQL_C_SSHORT, @OrdinalPosition, SizeOf(OrdinalPosition), @cbOrdinalPosition));
    ODBCException(Stmt, SQLBindCol(Stmt, 9, SQL_C_WCHAR, @ColumnName, SizeOf(ColumnName), @cbColumnName));
    ODBCException(Stmt, SQLBindCol(Stmt, 10, SQL_C_WCHAR, @AscOrDesc[0], SizeOf(AscOrDesc), @cbAscOrDesc));

    while (SQL_SUCCEEDED(ODBCException(Stmt, SQLFetch(Stmt)))) do
      if ((IndexType in [SQL_INDEX_CLUSTERED, SQL_INDEX_HASHED, SQL_INDEX_OTHER])) then
      begin
        Key := NewTable.IndexByName(IndexName);

        if (not Assigned(Key)) then
        begin
          Key := TSKey.Create(NewTable.Keys);
          Key.Name := Session.ApplyIdentifierName(IndexName);
          Key.Unique := NonUnique = SQL_FALSE;
          NewTable.Keys.AddKey(Key);
          Key.Free();

          Key := NewTable.IndexByName(IndexName);
        end;

        NewKeyColumn := TSKeyColumn.Create(Key.Columns);
        NewKeyColumn.Field := NewTable.FieldByName(ColumnName);
        NewKeyColumn.Ascending := AscOrDesc[0] = 'A';
        Key.Columns.AddColumn(NewKeyColumn);
        FreeAndNil(NewKeyColumn);
      end;

    SQLFreeHandle(SQL_HANDLE_STMT, Stmt);


    if ((NewTable.Keys.Count > 0) and not Assigned(NewTable.IndexByName(''))) then
    begin
      Key := nil;
      for I := NewTable.Keys.Count - 1 downto 0 do
        if ((SysUtils.UpperCase(NewTable.Keys[I].Name) = 'PRIMARYKEY') and NewTable.Keys[0].Unique) then
          Key := NewTable.Keys[I];
      if (Assigned(Key)) then
      begin
        Key.Primary := True;
        Key.Name := '';
      end;
    end;

    if ((NewTable.Keys.Count > 0) and not NewTable.Keys[0].Primary and NewTable.Keys[0].Unique) then
    begin
      NewTable.Keys[0].Primary := True;
      NewTable.Keys[0].Name := '';
    end;

    for I := 0 to NewTable.Fields.Count -1 do
      if ((NewTable.Keys.Count = 0) and NewTable.Fields[I].AutoIncrement) then
      begin
        Key := TSKey.Create(NewTable.Keys);
        Key.Primary := True;
        NewTable.Keys.AddKey(Key);
        Key.Free();

        Key := NewTable.Keys[0];

        NewKeyColumn := TSKeyColumn.Create(Key.Columns);
        NewKeyColumn.Field := TSBaseTableField(NewTable.Fields[I]);
        Key.Columns.AddColumn(NewKeyColumn);
        FreeAndNil(NewKeyColumn);
      end;

    for I := NewTable.Keys.Count - 1 downto 1 do
      for J := I - 1 downto 0 do
        if (I <> J) then
          if (NewTable.Keys[J].Equal(NewTable.Keys[I])) then
            NewTable.Keys.DeleteKey(NewTable.Keys[J])
          else if (SysUtils.UpperCase(NewTable.Keys[I].Name) = SysUtils.UpperCase(NewTable.Keys[J].Name)) then
            NewTable.Keys[I].Name := 'Index_' + IntToStr(I);

    Found := False;
    for I := 0 to NewTable.Fields.Count - 1 do
    begin
      NewTable.Fields[I].AutoIncrement := not Found and NewTable.Fields[I].AutoIncrement and (NewTable.Keys.Count > 0) and (NewTable.Keys[0].Name = '') and (NewTable.Keys[0].Columns.KeyByField(NewTable.Fields[I]) >= 0);
      Found := Found or NewTable.Fields[I].AutoIncrement;
      if (NewTable.Fields[I].AutoIncrement) then
        NewTable.Fields[I].Default := '';
    end;

    Found := False;
    for I := 0 to NewTable.Fields.Count - 1 do
    begin
      if (Found and (NewTable.Fields[I].Default = 'CURRENT_TIMESTAMP')) then
        NewTable.Fields[I].Default := '';
      Found := Found or (NewTable.Fields[I].Default = 'CURRENT_TIMESTAMP');
    end;

    NewTable.Name := Session.ApplyIdentifierName(Item.TableName);

    Session.BeginSynchron();
    while ((Success <> daAbort) and not Database.AddTable(NewTable)) do
      DoError(DatabaseError(Session), Item, True);
    Session.EndSynchron();
  end;

  NewTable.Free();

  Table := Database.BaseTableByName(Item.TableName);
  if (not Assigned(Table)) then
    SetLength(Fields, 0)
  else
  begin
    SetLength(Fields, Table.Fields.Count);
    for I := 0 to Table.Fields.Count - 1 do
      Fields[I] := Table.Fields[I];
  end;
end;

function TTImportBaseODBC.GetFieldNames(const TableName: string; const FieldNames: TStrings): Boolean;
var
  cbCOLUMN_NAME: SQLINTEGER;
  COLUMN_NAME: array [0 .. STR_LEN] of SQLWCHAR;
  Stmt: SQLHSTMT;
  FieldName: string;
begin
  Success := daSuccess;

  Open();

  Result := False;
  if (Success = daSuccess) then
    if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, FHandle, @Stmt))) then
      raise ERangeError.Create(SRangeError)
    else if (not SQL_SUCCEEDED(SQLColumns(Stmt, nil, 0, nil, 0, PSQLTCHAR(PChar(TableName)), SQL_NTS, nil, 0))) then
      DoError(ODBCError(SQL_HANDLE_STMT, Stmt), nil, True)
    else
    begin
      ODBCException(Handle, SQLBindCol(Stmt, 4, SQL_C_WCHAR, @COLUMN_NAME, SizeOf(COLUMN_NAME), @cbCOLUMN_NAME));
      while (SQL_SUCCEEDED(ODBCException(Stmt, SQLFetch(Stmt)))) do
      begin
        SetString(FieldName, PChar(@COLUMN_NAME), cbCOLUMN_NAME);
        FieldNames.Add(FieldName);
      end;

      SQLFreeHandle(SQL_HANDLE_STMT, Stmt);

      Result := True;
    end;
end;

function TTImportBaseODBC.GetTableNames(const TableNames: TStrings): Boolean;
const
  TABLE_TYPE_LEN = 30;
var
  cbTABLE_NAME: SQLINTEGER;
  cbTABLE_TYPE: SQLINTEGER;
  Stmt: SQLHSTMT;
  TableName: string;
  TABLE_NAME: PSQLTCHAR;
  TABLE_NAME_LEN: SQLINTEGER;
  TABLE_TYPE: PSQLTCHAR;
begin
  Success := daSuccess;

  Open();

  Result := False;
  if (Success = daSuccess) then
    if (not SQL_SUCCEEDED(SQLGetInfo(Handle, SQL_MAX_TABLE_NAME_LEN, @TABLE_NAME_LEN, SizeOf(TABLE_NAME_LEN), nil))) then
      DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False)
    else if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, FHandle, @Stmt))) then
      raise ERangeError.Create(SRangeError)
    else
    begin
      GetMem(TABLE_NAME, (TABLE_NAME_LEN + 1) * SizeOf(SQLWCHAR));
      GetMem(TABLE_TYPE, (TABLE_TYPE_LEN + 1) * SizeOf(SQLWCHAR));

      if (not SQL_SUCCEEDED(SQLTables(Stmt, nil, 0, nil, 0, nil, 0, nil, 0))
        or not SQL_SUCCEEDED(SQLBindCol(Stmt, 3, SQL_C_WCHAR, TABLE_NAME, (TABLE_NAME_LEN + 1) * SizeOf(SQLWCHAR), @cbTABLE_NAME))
        or not SQL_SUCCEEDED(SQLBindCol(Stmt, 4, SQL_C_WCHAR, TABLE_TYPE, (TABLE_TYPE_LEN + 1) * SizeOf(SQLWCHAR), @cbTABLE_TYPE))) then
        DoError(ODBCError(SQL_HANDLE_STMT, Stmt), nil, False)
      else
      begin
        while (SQL_SUCCEEDED(ODBCException(Stmt, SQLFetch(Stmt)))) do
          if ((lstrcmpi(PChar(TABLE_TYPE), 'TABLE') = 0) or (Self is TTImportExcel) and ((lstrcmpi(PChar(TABLE_TYPE), 'TABLE') = 0) or (lstrcmpi(PChar(TABLE_TYPE), 'SYSTEM TABLE') = 0)))  then
          begin
            SetString(TableName, PChar(TABLE_NAME), cbTABLE_NAME div SizeOf(SQLTCHAR));
            TableNames.Add(TableName);
          end;
        SQLFreeStmt(Stmt, SQL_CLOSE);

        if ((Self is TTImportExcel) and (TableNames.Count = 0)) then
          if (not SQL_SUCCEEDED(SQLTables(Stmt, nil, 0, nil, 0, nil, 0, nil, 0))
            or not SQL_SUCCEEDED(SQLBindCol(Stmt, 3, SQL_C_WCHAR, TABLE_NAME, (TABLE_NAME_LEN + 1) * SizeOf(SQLWCHAR), @cbTABLE_NAME))
            or not SQL_SUCCEEDED(SQLBindCol(Stmt, 4, SQL_C_WCHAR, TABLE_TYPE, (TABLE_TYPE_LEN + 1) * SizeOf(SQLWCHAR), @cbTABLE_TYPE))) then
            raise ERangeError.Create(SRangeError)
          else
          begin
            while (SQL_SUCCEEDED(ODBCException(Stmt, SQLFetch(Stmt)))) do
              if (lstrcmpi(PChar(TABLE_TYPE), 'TABLE') = 0)  then
              begin
                SetString(TableName, PChar(TABLE_NAME), cbTABLE_NAME div SizeOf(SQLTCHAR));
                TableNames.Add(TableName);
              end;
            SQLFreeStmt(Stmt, SQL_CLOSE);
          end;

        Result := True;
      end;

      FreeMem(TABLE_NAME);
      FreeMem(TABLE_TYPE);
      SQLFreeHandle(SQL_HANDLE_STMT, Stmt);
    end;
end;

function TTImportBaseODBC.GetValues(const Item: TTImport.TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean;
var
  cbData: SQLINTEGER;
  I: Integer;
  ReturnCode: SQLRETURN;
  Size: Integer;
begin
  Result := SQL_SUCCEEDED(ODBCException(Stmt, SQLFetch(Stmt)));

  if (Result) then
  begin
    for I := 0 to Length(Fields) - 1 do
    begin
      if (I > 0) then
        DataFileBuffer.Write(PAnsiChar(',_'), 1); // Two characters are needed to instruct the compiler to give a pointer - but the first character should be placed in the file only

      case (ColumnDesc[I].SQLDataType) of
        SQL_BIT,
        SQL_TINYINT,
        SQL_SMALLINT,
        SQL_INTEGER,
        SQL_BIGINT,
        SQL_DECIMAL,
        SQL_NUMERIC,
        SQL_REAL,
        SQL_FLOAT,
        SQL_DOUBLE,
        SQL_TYPE_DATE,
        SQL_TYPE_TIME,
        SQL_TYPE_TIMESTAMP:
          if (not SQL_SUCCEEDED(SQLGetData(Stmt, I + 1, SQL_C_CHAR, ODBCData, ODBCDataSize, @cbData))) then
          begin
            DoError(ODBCError(SQL_HANDLE_STMT, Stmt), Item, False);
            DataFileBuffer.Write(PAnsiChar('NULL'), 4)
          end
          else if (cbData = SQL_NULL_DATA) then
            DataFileBuffer.Write(PAnsiChar('NULL'), 4)
          else
            DataFileBuffer.Write(PSQLACHAR(ODBCData), cbData div SizeOf(SQLACHAR), ColumnDesc[I].SQLDataType in [SQL_TYPE_DATE, SQL_TYPE_TIMESTAMP, SQL_TYPE_TIME]);
        SQL_CHAR,
        SQL_VARCHAR,
        SQL_LONGVARCHAR,
        SQL_WCHAR,
        SQL_WVARCHAR,
        SQL_WLONGVARCHAR:
          begin
            Size := 0;
            repeat
              ReturnCode := SQLGetData(Stmt, I + 1, SQL_C_WCHAR, ODBCData, ODBCDataSize, @cbData);
              if ((cbData <> SQL_NULL_DATA) and (cbData > 0)) then
              begin
                if (ODBCMemSize < Size + cbData) then
                begin
                  ODBCMemSize := ODBCMemSize + 2 * (Size + cbData - ODBCMemSize);
                  ReallocMem(ODBCMem, ODBCMemSize);
                end;
                MoveMemory(@PAnsiChar(ODBCMem)[Size], ODBCData, cbData);
                Inc(Size, cbData);
              end;
            until (ReturnCode <> SQL_SUCCESS_WITH_INFO);
            if (not SQL_SUCCEEDED(ReturnCode)) then
            begin
              DoError(ODBCError(SQL_HANDLE_STMT, Stmt), Item, False);
              DataFileBuffer.Write(PAnsiChar('NULL'), 4);
            end
            else if ((Size = 0) and (cbData = SQL_NULL_DATA)) then
              DataFileBuffer.Write(PAnsiChar('NULL'), 4)
            else
              DataFileBuffer.WriteText(PChar(ODBCMem), Size div SizeOf(Char));
          end;
        SQL_BINARY,
        SQL_VARBINARY,
        SQL_LONGVARBINARY:
          begin
            Size := 0;
            repeat
              ReturnCode := SQLGetData(Stmt, I + 1, SQL_C_BINARY, ODBCData, ODBCDataSize, @cbData);
              if ((cbData <> SQL_NULL_DATA) and (cbData > 0)) then
              begin
                if (ODBCMemSize < Size + cbData) then
                begin
                  ODBCMemSize := ODBCMemSize + 2 * (Size + cbData - ODBCMemSize);
                  ReallocMem(ODBCMem, ODBCMemSize);
                end;
                MoveMemory(@PAnsiChar(ODBCMem)[Size], ODBCData, cbData);
                Inc(Size, cbData);
              end;
            until (ReturnCode <> SQL_SUCCESS_WITH_INFO);
            if (not SQL_SUCCEEDED(ReturnCode)) then
            begin
              DoError(ODBCError(SQL_HANDLE_STMT, Stmt), Item, False);
              DataFileBuffer.Write(PAnsiChar('NULL'), 4);
            end
            else if (cbData = SQL_NULL_DATA) then
              DataFileBuffer.Write(PAnsiChar('NULL'), 4)
            else
              DataFileBuffer.WriteBinary(my_char(ODBCMem), Size);
          end;
        else
          raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [Fields[I].Name, ColumnDesc[I].SQLDataType]);
      end;
    end;
  end;
end;

function TTImportBaseODBC.GetValues(const Item: TTImport.TItem; var Values: TSQLStrings): Boolean;
var
  Bytes: TBytes;
  cbData: SQLINTEGER;
  D: Double;
  I: Integer;
  ReturnCode: SQLRETURN;
  S: string;
  Timestamp: tagTIMESTAMP_STRUCT;
begin
  Result := SQL_SUCCEEDED(ODBCException(Stmt, SQLFetch(Stmt)));
  if (Result) then
    for I := 0 to Length(Fields) - 1 do
      case (ColumnDesc[I].SQLDataType) of
        SQL_BIT,
        SQL_TINYINT,
        SQL_SMALLINT,
        SQL_INTEGER,
        SQL_BIGINT:
          if (not SQL_SUCCEEDED(SQLGetData(Stmt, I + 1, SQL_C_WCHAR, ODBCData, ODBCDataSize, @cbData))) then
            ODBCException(Stmt, SQL_ERROR)
          else if (cbData = SQL_NULL_DATA) then
            Values[I] := 'NULL'
          else
          begin
            SetString(S, PChar(ODBCData), cbData div SizeOf(Char));
            Values[I] := Fields[I].EscapeValue(S);
          end;
        SQL_DECIMAL,
        SQL_NUMERIC,
        SQL_REAL,
        SQL_FLOAT,
        SQL_DOUBLE:
          if (not SQL_SUCCEEDED(SQLGetData(Stmt, I + 1, SQL_C_DOUBLE, @D, SizeOf(D), @cbData))) then
            ODBCException(Stmt, SQL_ERROR)
          else if (cbData = SQL_NULL_DATA) then
            Values[I] := 'NULL'
          else
            Values[I] := Fields[I].EscapeValue(FloatToStr(D, Session.FormatSettings));
        SQL_DATETIME,
        SQL_TYPE_DATE,
        SQL_TYPE_TIME,
        SQL_TYPE_TIMESTAMP:
          if (not SQL_SUCCEEDED(SQLGetData(Stmt, I + 1, SQL_C_TYPE_TIMESTAMP, @Timestamp, SizeOf(Timestamp), @cbData))) then
            ODBCException(Stmt, SQL_ERROR)
          else if (cbData = SQL_NULL_DATA) then
            Values[I] := 'NULL'
          else
            with (Timestamp) do
              if (ColumnDesc[I].SQLDataType = SQL_TYPE_TIME) then
                Values[I] := TimeToStr(EncodeTime(hour, minute, second, 0), Session.FormatSettings)
              else if (ColumnDesc[I].SQLDataType in [SQL_DATETIME, SQL_TYPE_TIMESTAMP]) then
                Values[I] := MySQLDB.DateTimeToStr(EncodeDate(year, month, day) + EncodeTime(hour, minute, second, 0), Session.FormatSettings)
              else if (ColumnDesc[I].SQLDataType = SQL_TYPE_DATE) then
                Values[I] := MySQLDB.DateToStr(EncodeDate(year, month, day) + EncodeTime(hour, minute, second, 0), Session.FormatSettings);
        SQL_CHAR,
        SQL_VARCHAR,
        SQL_LONGVARCHAR,
        SQL_WCHAR,
        SQL_WVARCHAR,
        SQL_WLONGVARCHAR:
          begin
            SetLength(S, 0);
            repeat
              ReturnCode := SQLGetData(Stmt, I + 1, SQL_C_WCHAR, ODBCData, ODBCDataSize, @cbData);
              if (cbData <> SQL_NULL_DATA) then
              begin
                SetLength(S, Length(S) + cbData div SizeOf(SQLTCHAR));
                if (cbData > 0) then
                  MoveMemory(@S[1 + Length(S) - cbData div SizeOf(SQLTCHAR)], ODBCData, cbData);
              end;
            until (ReturnCode <> SQL_SUCCESS_WITH_INFO);
            if (not SQL_SUCCEEDED(ReturnCode)) then
              ODBCException(Stmt, ReturnCode)
            else if (cbData = SQL_NULL_DATA) then
              Values[I] := 'NULL'
            else
              Values[I] := S;
          end;
        SQL_BINARY,
        SQL_VARBINARY,
        SQL_LONGVARBINARY:
          begin
            SetLength(Bytes, 0);
            repeat
              ReturnCode := SQLGetData(Stmt, I + 1, SQL_C_BINARY, ODBCData, ODBCDataSize, @cbData);
              if (cbData <> SQL_NULL_DATA) then
              begin
                SetLength(Bytes, Length(Bytes) + cbData);
                if (cbData > 0) then
                  MoveMemory(@Bytes[Length(Bytes) - cbData], ODBCData, cbData);
              end;
            until (ReturnCode <> SQL_SUCCESS_WITH_INFO);
            if (not SQL_SUCCEEDED(ReturnCode)) then
              ODBCException(Stmt, ReturnCode)
            else if (cbData = SQL_NULL_DATA) then
              Values[I] := 'NULL'
            else
              SetString(Values[I], PChar(@Bytes[0]), Length(Bytes));
          end;
        else
          raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [Fields[I].Name, Ord(Fields[I].FieldType)]);
      end;
end;

function TTImportBaseODBC.ODBCStmtException(const AStmt: SQLHSTMT): Exception;
var
  MessageText: array [0 .. STR_LEN] of SQLTCHAR;
  NativeErrorPtr: SQLSMALLINT;
  SQLState: array [0 .. SQL_SQLSTATE_SIZE] of SQLTCHAR;
  TextLengthPtr: SQLSMALLINT;
begin
  SQLGetDiagRec(SQL_HANDLE_STMT, AStmt, 1, @SQLState, @NativeErrorPtr, @MessageText, Length(MessageText), @TextLengthPtr);
  Result := Exception.Create(string(MessageText) + ' (' + SQLState + ')');
end;

{ TTImportODBC ****************************************************************}

constructor TTImportODBC.Create(const ASession: TSSession; const ADatabase: TSDatabase; const ADataSource, AUsername, APassword: string);
begin
  inherited Create(ASession, ADatabase);

  FDataSource := ADataSource;
  FUsername := AUsername;
  FPassword := APassword;
end;

procedure TTImportODBC.Open();
begin
  if (FHandle = SQL_NULL_HANDLE) then
  begin
    if ((Success = daSuccess) and not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_DBC, ODBCEnv, @FHandle))) then
      DoError(ODBCError(SQL_HANDLE_ENV, ODBCEnv), nil, False);

    while ((Success <> daAbort) and not SQL_SUCCEEDED(SQLConnect(FHandle, PSQLTCHAR(PChar(FDataSource)), SQL_NTS, PSQLTCHAR(PChar(FUsername)), SQL_NTS, PSQLTCHAR(PChar(FPassword)), SQL_NTS))) do
      DoError(ODBCError(SQL_HANDLE_DBC, FHandle), nil, True);
  end;
end;

{ TTImportAccess **************************************************************}

constructor TTImportAccess.Create(const ASession: TSSession; const ADatabase: TSDatabase; const AFilename: string);
begin
  inherited Create(ASession, ADatabase);

  FFilename := AFilename;
end;

procedure TTImportAccess.Open();
var
  Connected: Boolean;
  ConnStrIn: string;
begin
  if (FHandle = SQL_NULL_HANDLE) then
  begin
    if ((Success = daSuccess) and not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_DBC, ODBCEnv, @FHandle))) then
      DoError(ODBCError(SQL_HANDLE_ENV, ODBCEnv), nil, False);

    Connected := False;
    while ((Success <> daAbort) and not Connected) do
    begin
      ConnStrIn := 'Driver={Microsoft Access Driver (*.mdb, *.accdb)};' + 'DBQ=' + FFilename + ';' + 'READONLY=TRUE';
      Connected := SQL_SUCCEEDED(SQLDriverConnect(FHandle, Application.Handle, PSQLTCHAR(ConnStrIn), SQL_NTS, nil, 0, nil, SQL_DRIVER_COMPLETE));
      if (not Connected) then
      begin
        ConnStrIn := 'Driver={Microsoft Access Driver (*.mdb)};' + 'DBQ=' + FFilename + ';' + 'READONLY=TRUE';
        Connected := SQL_SUCCEEDED(SQLDriverConnect(FHandle, Application.Handle, PSQLTCHAR(ConnStrIn), SQL_NTS, nil, 0, nil, SQL_DRIVER_COMPLETE));
      end;
      if (not Connected) then
        DoError(ODBCError(SQL_HANDLE_DBC, FHandle), nil, True);
    end;
  end;
end;

{ TTImportExcel **************************************************************}

constructor TTImportExcel.Create(const ASession: TSSession; const ADatabase: TSDatabase; const AFilename: string);
begin
  inherited Create(ASession, ADatabase);

  FFilename := AFilename;
end;

procedure TTImportExcel.Open();
var
  Connected: Boolean;
  ConnStrIn: string;
begin
  if (FHandle = SQL_NULL_HANDLE) then
  begin
    if ((Success = daSuccess) and not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_DBC, ODBCEnv, @FHandle))) then
      DoError(ODBCError(SQL_HANDLE_ENV, ODBCEnv), nil, False);

    Connected := False;
    while ((Success <> daAbort) and not Connected) do
    begin
      ConnStrIn := 'Driver={Microsoft Excel Driver (*.xls, *.xlsx, *.xlsm, *.xlsb)};' + 'DBQ=' + FFilename + ';' + 'READONLY=TRUE';
      Connected := SQL_SUCCEEDED(SQLDriverConnect(FHandle, Application.Handle, PSQLTCHAR(ConnStrIn), SQL_NTS, nil, 0, nil, SQL_DRIVER_COMPLETE));
      if (not Connected) then
      begin
        ConnStrIn := 'Driver={Microsoft Excel Driver (*.xls)};' + 'DBQ=' + FFilename + ';' + 'READONLY=TRUE';
        Connected := SQL_SUCCEEDED(SQLDriverConnect(FHandle, Application.Handle, PSQLTCHAR(ConnStrIn), SQL_NTS, nil, 0, nil, SQL_DRIVER_COMPLETE));
      end;
      if (not Connected) then
        DoError(ODBCError(SQL_HANDLE_DBC, FHandle), nil, True);
    end;
  end;
end;

{ TTImportXML *****************************************************************}

procedure TTImportXML.BeforeExecute();
var
  Error: TTool.TError;
begin
  inherited;

  if (not XMLDocument.load(Filename)) then
  begin
    Error.ErrorType := TE_XML;
    Error.ErrorCode := XMLDocument.parseError.errorCode;
    Error.ErrorMessage := XMLDocument.parseError.reason;
    if (XMLDocument.parseError.srcText <> '') then
      Error.ErrorMessage := Error.ErrorMessage + ' near "' + Copy(XMLDocument.parseError.srcText, 1, 20) + '"';
    if (XMLDocument.parseError.line > 0) then
    begin
      Error.ErrorMessage := Error.ErrorMessage + ' in line ' + IntToStr(XMLDocument.parseError.line);
      if (XMLDocument.parseError.linepos > 0) then
        Error.ErrorMessage := Error.ErrorMessage + ', at position ' + IntToStr(XMLDocument.parseError.line);
    end;
    DoError(Error, nil, False);
  end;
end;

procedure TTImportXML.BeforeExecuteData(const Item: TTImport.TItem);
var
  Error: TTool.TError;
begin
  inherited;

  XMLNode := XMLDocument.documentElement.selectSingleNode('//*/' + Item.SourceTableName);

  if (not Assigned(XMLNode)) then
  begin
    Error.ErrorType := TE_XML;
    Error.ErrorCode := 0;
    Error.ErrorMessage := '[MSXML] Node <' + Item.SourceTableName + '> not found.';
    DoError(Error, nil, False);
  end;

  if (Assigned(XMLNode)) then
    Item.RecordsSum := XMLNode.parentNode.childNodes.length;
end;

constructor TTImportXML.Create(const AFilename: TFileName; const ATable: TSBaseTable);
begin
  inherited Create(ATable.Database.Session, ATable.Database);

  Add(ATable.Name);

  Filename := AFilename;
  Data := True;

  XMLDocument := CoDOMDocument30.Create();
end;

function TTImportXML.GetValues(const Item: TTImport.TItem; const DataFileBuffer: TTool.TDataFileBuffer): Boolean;
var
  I: Integer;
  J: Integer;
  XMLValueNode: IXMLDOMNode;
begin
  Result := Assigned(XMLNode);
  if (Result) then
  begin
    for I := 0 to Length(Fields) - 1 do
    begin
      XMLValueNode := XMLNode.selectSingleNode('@' + SysUtils.LowerCase(SourceFields[I].Name));
      if (not Assigned(XMLValueNode)) then
      begin
        XMLValueNode := XMLNode.selectSingleNode(SysUtils.LowerCase(SourceFields[I].Name));
        for J := 0 to XMLNode.childNodes.length - 1 do
          if (not Assigned(XMLValueNode) and (XMLNode.childNodes[J].nodeName = 'field') and Assigned(XMLNode.childNodes[J].selectSingleNode('@name')) and (lstrcmpI(PChar(XMLNode.childNodes[J].selectSingleNode('@name').text), PChar(SourceFields[I].Name)) = 0)) then
            XMLValueNode := XMLNode.childNodes[J];
      end;

      if (I > 0) then
        DataFileBuffer.Write(PAnsiChar(',_'), 1); // Two characters are needed to instruct the compiler to give a pointer - but the first character should be placed in the file only
      if (not Assigned(XMLValueNode) or (XMLValueNode.text = '') and Assigned(XMLValueNode.selectSingleNode('@xsi:nil')) and (XMLValueNode.selectSingleNode('@xsi:nil').text = 'true')) then
        DataFileBuffer.Write(PAnsiChar('NULL'), 4)
      else if (Fields[I].FieldType in BinaryFieldTypes) then
        DataFileBuffer.WriteBinary(PChar(XMLValueNode.text), Length(XMLValueNode.text))
      else if (Fields[I].FieldType in TextFieldTypes) then
        DataFileBuffer.WriteText(PChar(XMLValueNode.text), Length(XMLValueNode.text))
      else
        DataFileBuffer.WriteData(PChar(XMLValueNode.text), Length(XMLValueNode.text), not (Fields[I].FieldType in NotQuotedFieldTypes));
    end;

    repeat
      XMLNode := XMLNode.nextSibling;
    until (not Assigned(XMLNode) or (XMLNode.nodeName = Item.SourceTableName));
  end;
end;

function TTImportXML.GetValues(const Item: TTImport.TItem; var Values: TSQLStrings): Boolean;
var
  I: Integer;
  J: Integer;
  XMLValueNode: IXMLDOMNode;
begin
  Result := Assigned(XMLNode);
  if (Result) then
  begin
    for I := 0 to Length(Fields) - 1 do
    begin
      XMLValueNode := XMLNode.selectSingleNode('@' + SysUtils.LowerCase(SourceFields[I].Name));
      if (not Assigned(XMLValueNode)) then
      begin
        XMLValueNode := XMLNode.selectSingleNode(SysUtils.LowerCase(SourceFields[I].Name));
        for J := 0 to XMLNode.childNodes.length - 1 do
          if (not Assigned(XMLValueNode) and (XMLNode.childNodes[J].nodeName = 'field') and Assigned(XMLNode.childNodes[J].selectSingleNode('@name')) and (XMLNode.childNodes[J].selectSingleNode('@name').text = SourceFields[I].Name)) then
            XMLValueNode := XMLNode.childNodes[J];
      end;

      if (not Assigned(XMLValueNode) or (XMLValueNode.text = '') and Assigned(XMLValueNode.selectSingleNode('@xsi:nil')) and (XMLValueNode.selectSingleNode('@xsi:nil').text = 'true')) then
        Values[I] := 'NULL'
      else
        Values[I] := XMLValueNode.text;
    end;

    repeat
      XMLNode := XMLNode.nextSibling;
    until (not Assigned(XMLNode) or (XMLNode.nodeName = Item.SourceTableName));
  end;
end;

{ TTExport.TDataSetItem *******************************************************}

constructor TTExport.TDataSetItem.Create(const AItems: TTool.TItems; const ADataSet: TMySQLDataSet);
begin
  inherited Create(AItems);

  FDataSet := ADataSet;
end;

{ TTExport ********************************************************************}

procedure TTExport.Add(const ADataSet: TMySQLDataSet);
var
  NewItem: TDataSetItem;
begin
  NewItem := TDataSetItem.Create(Items, ADataSet);
  Items.Add(NewItem);
end;

procedure TTExport.Add(const ADBObject: TSDBObject);
var
  NewItem: TDBObjectItem;
begin
  NewItem := TDBObjectItem.Create(Items, ADBObject);
  Items.Add(NewItem);
end;

procedure TTExport.AfterExecute();
var
  I: Integer;
begin
  for I := 0 to Items.Count - 1 do
    if (Items[I] is TDataSetItem) then
      TDataSetItem(Items[I]).DataSet.EnableControls();

  FSession.EndSilent();
  FSession.EndSynchron();

  inherited;
end;

procedure TTExport.BeforeExecute();
var
  I: Integer;
begin
  inherited;

  FSession.BeginSynchron(); // We're still in a thread
  FSession.BeginSilent();

  for I := 0 to Items.Count - 1 do
    if (Items[I] is TDataSetItem) then
      TDataSetItem(Items[I]).DataSet.DisableControls();

  if ((Self is TTExportSQL) or (Self is TTTransfer)) then
    Items.Sort(TToolItemCompareForSQL)
  else
    Items.Sort(TToolItemCompare);
end;

constructor TTExport.Create(const ASession: TSSession);
begin
  inherited Create();

  FSession := ASession;

  Data := False;
  Structure := False;
end;

procedure TTExport.DoUpdateGUI();
var
  I: Integer;
begin
  if (Assigned(OnUpdate)) then
  begin
    CriticalSection.Enter();

    ProgressInfos.TablesDone := 0;
    ProgressInfos.TablesSum := Items.Count;
    ProgressInfos.RecordsDone := 0;
    ProgressInfos.RecordsSum := 0;
    ProgressInfos.TimeDone := 0;
    ProgressInfos.TimeSum := 0;

    for I := 0 to Items.Count - 1 do
    begin
      if (TItem(Items[I]).Done) then
        Inc(ProgressInfos.TablesDone);
      Inc(ProgressInfos.RecordsDone, Items[I].RecordsDone);
      Inc(ProgressInfos.RecordsSum, Items[I].RecordsSum);
    end;

    ProgressInfos.TimeDone := Now() - StartTime;

    if ((ProgressInfos.RecordsDone = 0) and (ProgressInfos.TablesDone = 0)) then
    begin
      ProgressInfos.Progress := 0;
      ProgressInfos.TimeSum := 0;
    end
    else if (ProgressInfos.RecordsDone = 0) then
    begin
      ProgressInfos.Progress := Round(ProgressInfos.TablesDone / ProgressInfos.TablesSum * 100);
      ProgressInfos.TimeSum := ProgressInfos.TimeDone / ProgressInfos.TablesDone * ProgressInfos.TablesSum;
    end
    else if (ProgressInfos.RecordsDone < ProgressInfos.RecordsSum) then
    begin
      ProgressInfos.Progress := Round(ProgressInfos.RecordsDone / ProgressInfos.RecordsSum * 100);
      ProgressInfos.TimeSum := ProgressInfos.TimeDone / ProgressInfos.RecordsDone * ProgressInfos.RecordsSum;
    end
    else
    begin
      ProgressInfos.Progress := 100;
      ProgressInfos.TimeSum := ProgressInfos.TimeDone;
    end;

    CriticalSection.Leave();

    OnUpdate(ProgressInfos);
  end;
end;

procedure TTExport.Execute();
var
  DataHandle: TMySQLConnection.TDataResult;
  DataTables: TList;
  DataTablesIndex: Integer;
  FieldNames: string;
  I: Integer;
  Index: Integer;
  J: Integer;
  Objects: TList;
  SQL: string;
  Table: TSBaseTable;
begin
  {$IFDEF EurekaLog}
  try
  {$ENDIF}

  BeforeExecute();

  if (Success <> daAbort) then
  begin
    Objects := TList.Create();
    for I := 0 to Items.Count - 1 do
      if (Items[I] is TDBObjectItem) then
        Objects.Add(TDBObjectItem(Items[I]).DBObject);
    if (Objects.Count > 0) then
    begin
      Success := daSuccess;
      while ((Success = daSuccess) and not Session.Update(Objects)) do
        DoError(DatabaseError(Session), nil, True, SQL);
    end;
    Objects.Free();
  end;

  DataTables := TList.Create();

  SQL := '';
  if ((Success = daSuccess) and Data) then
  begin
    for I := 0 to Items.Count - 1 do
      if (Items[I] is TDataSetItem) then
        TDataSetItem(Items[I]).RecordsSum := TDataSetItem(Items[I]).DataSet.RecordCount
      else if ((Items[I] is TDBObjectItem)
        and (TDBObjectItem(Items[I]).DBObject is TSBaseTable)
        and not TSBaseTable(TDBObjectItem(Items[I]).DBObject).Engine.IsMerge
        and (not (Self is TTTransfer) or (TTTransfer(Self).DestinationSession <> Session))) then
      begin
        TDBObjectItem(Items[I]).RecordsSum := TSBaseTable(TDBObjectItem(Items[I]).DBObject).Rows;
        DataTables.Add(TSBaseTable(TDBObjectItem(Items[I]).DBObject));
      end;

    for I := 0 to DataTables.Count - 1 do
    begin
      Table := TSBaseTable(DataTables[I]);

      if (Length(TableFields) = 0) then
        FieldNames := '*'
      else
      begin
        FieldNames := '';
        for J := 0 to Length(TableFields) - 1 do
        begin
          if (FieldNames <> '') then FieldNames := FieldNames + ',';
          FieldNames := FieldNames + Session.EscapeIdentifier(TableFields[J].Name);
        end;
      end;

      SQL := SQL + 'SELECT ' + FieldNames + ' FROM ' + Session.EscapeIdentifier(Table.Database.Name) + '.' + Session.EscapeIdentifier(Table.Name);
      if ((Table is TSBaseTable) and Assigned(TSBaseTable(Table).PrimaryKey)) then
      begin
        SQL := SQL + ' ORDER BY ';
        for J := 0 to TSBaseTable(Table).PrimaryKey.Columns.Count - 1 do
        begin
          if (J > 0) then SQL := SQL + ',';
          SQL := SQL + Session.EscapeIdentifier(TSBaseTable(Table).PrimaryKey.Columns[J].Field.Name);
        end;
      end;
      SQL := SQL + ';' + #13#10;
    end;
  end;

  if (Success <> daAbort) then
  begin
    Success := daSuccess;
    ExecuteHeader();
  end;

  if (Success <> daAbort) then
  begin
    DataHandle := nil;

    for I := 0 to Items.Count - 1 do
      if (Success <> daAbort) then
      begin
        if ((Success <> daAbort) and ((I = 0) or (TDBObjectItem(Items[I]).DBObject.Database <> TDBObjectItem(Items[I - 1]).DBObject.Database))) then
        begin
          Success := daSuccess;

          ExecuteDatabaseHeader(TDBObjectItem(Items[I]).DBObject.Database);
        end;

        if (Success <> daAbort) then
        begin
          Success := daSuccess;

          if (Items[I] is TDataSetItem) then
            ExecuteDataSet(TDataSetItem(Items[I]))
          else if (Items[I] is TDBObjectItem) then
          begin
            DataTablesIndex := DataTables.IndexOf(TDBObjectItem(Items[I]).DBObject);
            case (DataTablesIndex) of
              -1: ;
              0:
                while ((Success = daSuccess) and not Session.FirstResult(DataHandle, SQL)) do
                  DoError(DatabaseError(Session), nil, True, SQL);
              else
                if ((Success = daSuccess) and not Session.NextResult(DataHandle)) then
                  DoError(DatabaseError(Session), nil, False);
            end;

            if (Success <> daAbort) then
            begin
              Success := daSuccess;

              if (TDBObjectItem(Items[I]).DBObject is TSTable) then
                if (DataTablesIndex < 0) then
                  ExecuteTable(TDBObjectItem(Items[I]), nil)
                else
                  ExecuteTable(TDBObjectItem(Items[I]), DataHandle)
              else if (Structure) then
                if (TDBObjectItem(Items[I]).DBObject is TSRoutine) then
                  ExecuteRoutine(TSRoutine(TDBObjectItem(Items[I]).DBObject))
                else if (TDBObjectItem(Items[I]).DBObject is TSEvent) then
                  ExecuteEvent(TSEvent(TDBObjectItem(Items[I]).DBObject))
                else if ((TDBObjectItem(Items[I]).DBObject is TSTrigger) and (Self is TTExportSQL)) then
                  ExecuteTrigger(TSTrigger(TDBObjectItem(Items[I]).DBObject));
            end;
          end;
        end;

        if ((Success <> daAbort) and ((I = Items.Count - 1) or (TDBObjectItem(Items[I + 1]).DBObject.Database <> TDBObjectItem(Items[I]).DBObject.Database))) then
        begin
          Success := daSuccess;

          ExecuteDatabaseFooter(TDBObjectItem(Items[I]).DBObject.Database);
        end;

        TItem(Items[I]).Done := True;
      end;

    if (Assigned(DataHandle)) then
      Session.CloseResult(DataHandle);
  end;

  if (Success <> daAbort) then
  begin
    Success := daSuccess;
    ExecuteFooter();
  end;

  AfterExecute();

  DataTables.Free();

  {$IFDEF EurekaLog}
  except
    StandardEurekaNotify(GetLastExceptionObject(), GetLastExceptionAddress());
  end;
  {$ENDIF}
end;

procedure TTExport.ExecuteDatabaseFooter(const Database: TSDatabase);
begin
end;

procedure TTExport.ExecuteDatabaseHeader(const Database: TSDatabase);
begin
end;

procedure TTExport.ExecuteDataSet(const Item: TDataSetItem);
var
  Database: TSDatabase;
  DataSet: TMySQLDataSet;
  OldBookmark: TBookmark;
  OldLoadNextRecords: Boolean;
  Table: TSTable;
begin
  DataSet := TMySQLDataSet(Item.DataSet);
  if (Item.DataSet is TMySQLTable) then
  begin
    Database := Session.DatabaseByName(TMySQLTable(DataSet).DatabaseName);
    Table := Database.BaseTableByName(TMySQLTable(DataSet).TableName);
  end
  else
  begin
    Database := Session.DatabaseByName(DataSet.DatabaseName);
    if (not Assigned(Database) or not DataSet.CanModify) then
      Table := nil
    else
      Table := Database.TableByName(DataSet.TableName);
  end;

  if (not (DataSet is TMySQLTable)) then
    OldLoadNextRecords := False // hide compiler warning
  else
  begin
    OldLoadNextRecords := TMySQLTable(DataSet).AutomaticLoadNextRecords;
    TMySQLTable(DataSet).AutomaticLoadNextRecords := False;
  end;
  OldBookmark := DataSet.Bookmark;

  if (Success <> daAbort) then
  begin
    Success := daSuccess;
    ExecuteTableHeader(Table, Fields, DataSet);
  end;

  if ((Success <> daAbort) and DataSet.FindFirst()) then
    repeat
      ExecuteTableRecord(Table, Fields, DataSet);

      Inc(Item.RecordsDone);
      if (Item.RecordsDone mod 100 = 0) then DoUpdateGUI();

      if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
        Success := daAbort;
    until ((Success = daAbort) or not DataSet.FindNext());

  if (Success = daSuccess) then
    Item.RecordsSum := Item.RecordsDone;

  if (Success <> daAbort) then
  begin
    Success := daSuccess;
    ExecuteTableFooter(Table, Fields, DataSet);
  end;

  DataSet.Bookmark := OldBookmark;
  if (DataSet is TMySQLTable) then
    TMySQLTable(DataSet).AutomaticLoadNextRecords := OldLoadNextRecords;
end;

procedure TTExport.ExecuteEvent(const Event: TSEvent);
begin
end;

procedure TTExport.ExecuteFooter();
begin
end;

procedure TTExport.ExecuteHeader();
begin
end;

procedure TTExport.ExecuteRoutine(const Routine: TSRoutine);
begin
end;

procedure TTExport.ExecuteTable(const Item: TTool.TDBObjectItem; const DataHandle: TMySQLConnection.TDataResult);
var
  DataSet: TMySQLQuery;
  Fields: array of TField;
  I: Integer;
  SQL: string;
  Table: TSTable;
begin
  Table := TSTable(Item.DBObject);

  if (not Data or not Assigned(DataHandle)) then
    DataSet := nil
  else
  begin
    DataSet := TMySQLQuery.Create(nil);
    while ((Success <> daAbort) and not DataSet.Active) do
    begin
      DataSet.Open(DataHandle);
      if (not DataSet.Active) then
        DoError(DatabaseError(Session), Item, False, SQL);
    end;
  end;

  if ((Success <> daSuccess) or not Assigned(DataSet)) then
    SetLength(Fields, 0)
  else
  begin
    SetLength(Fields, DataSet.FieldCount);
    for I := 0 to DataSet.FieldCount - 1 do
      Fields[I] := DataSet.Fields[I];
  end;

  if (Success <> daAbort) then
  begin
    Success := daSuccess;

    ExecuteTableHeader(Table, Fields, DataSet);

    if ((Success <> daAbort) and Assigned(DataSet) and not DataSet.IsEmpty()) then
      repeat
        ExecuteTableRecord(Table, Fields, DataSet);

        Inc(Item.RecordsDone);
        if ((Item.RecordsDone mod 1000 = 0)
          or ((Item.RecordsDone mod 100 = 0) and (Self is TTExportBaseODBC))) then
          DoUpdateGUI();

        if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
          Success := daAbort;
      until ((Success <> daSuccess) or not DataSet.FindNext());

    if (Success <> daAbort) then
      Success := daSuccess;

    ExecuteTableFooter(Table, Fields, DataSet);
  end;

  if (Success = daSuccess) then
    Item.RecordsSum := Item.RecordsDone;

  if (Assigned(DataSet) and (Success <> daAbort)) then
    DataSet.Free();

  if ((Table is TSBaseTable) and not (Self is TTExportSQL)) then
    for I := 0 to TSBaseTable(Table).TriggerCount - 1 do
      if (Success = daSuccess) then
        ExecuteTrigger(TSBaseTable(Table).Triggers[I]);
end;

procedure TTExport.ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
end;

procedure TTExport.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
end;

procedure TTExport.ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
end;

procedure TTExport.ExecuteTrigger(const Trigger: TSTrigger);
begin
end;

{ TTExportFile ****************************************************************}

procedure TTExportFile.CloseFile();
begin
  if (Handle <> INVALID_HANDLE_VALUE) then
  begin
    Flush();

    CloseHandle(Handle);
    Handle := INVALID_HANDLE_VALUE;
  end;
end;

constructor TTExportFile.Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
begin
  inherited Create(ASession);

  ContentBuffer := TStringBuffer.Create(FilePacketSize);
  FCodePage := ACodePage;
  if (CodePage = CP_UNICODE) then
  begin
    FileBuffer.Size := 0;
    FileBuffer.Mem := nil;
  end
  else
  begin
    FileBuffer.Size := FilePacketSize;
    GetMem(FileBuffer.Mem, FileBuffer.Size);
  end;
  FFilename := AFilename;
  Handle := INVALID_HANDLE_VALUE;
end;

destructor TTExportFile.Destroy();
begin
  CloseFile();
  if (Assigned(FileBuffer.Mem)) then
    FreeMem(FileBuffer.Mem);
  ContentBuffer.Free();

  inherited;

  if (Success = daAbort) then
    DeleteFile(FFilename);
end;

procedure TTExportFile.DoFileCreate(const Filename: TFileName);
var
  Error: TTool.TError;
begin
  while ((Success <> daAbort) and not FileCreate(Filename, Error)) do
    DoError(Error, nil, True);
end;

function TTExportFile.FileCreate(const Filename: TFileName; out Error: TTool.TError): Boolean;
var
  Attributes: DWord;
begin
  if ((Self is TTExportText) and Assigned(TTExportText(Self).Zip)) then
    Attributes := FILE_ATTRIBUTE_TEMPORARY
  else
    Attributes := FILE_ATTRIBUTE_NORMAL;

  Handle := CreateFile(PChar(Filename),
                       GENERIC_WRITE,
                       FILE_SHARE_READ,
                       nil,
                       CREATE_ALWAYS, Attributes, 0);
  Result := Handle <> INVALID_HANDLE_VALUE;

  if (not Result) then
    Error := SysError();
end;

procedure TTExportFile.Flush();
var
  Buffer: PAnsiChar;
  BytesToWrite: DWord;
  BytesWritten: DWord;
  Size: DWord;
begin
  case (CodePage) of
    CP_UNICODE:
      begin
        Buffer := ContentBuffer.Data;
        BytesToWrite := ContentBuffer.Size;
      end;
    else
      begin
        BytesToWrite := WideCharToAnsiChar(CodePage, PChar(ContentBuffer.Data), ContentBuffer.Size div SizeOf(Char), nil, 0);
        if (BytesToWrite > FileBuffer.Size) then
        begin
          FileBuffer.Size := BytesToWrite;
          ReallocMem(FileBuffer.Mem, FileBuffer.Size);
        end;
        Buffer := FileBuffer.Mem;
        WideCharToAnsiChar(CodePage, PChar(ContentBuffer.Data), ContentBuffer.Size div SizeOf(Char), Buffer, BytesToWrite);
      end;
  end;

  BytesWritten := 0;
  while ((Success = daSuccess) and (BytesWritten < BytesToWrite)) do
    if (not WriteFile(Handle, Buffer[BytesWritten], BytesToWrite - BytesWritten, Size, nil)) then
      DoError(SysError(), nil, False)
    else
      Inc(BytesWritten, Size);

  ContentBuffer.Clear();
end;

procedure TTExportFile.WriteContent(const Content: string);
begin
  if (Content <> '') then
  begin
    if ((ContentBuffer.Size > 0) and (ContentBuffer.Size + Length(Content) * SizeOf(Content[1]) > FilePacketSize)) then
      Flush();

    ContentBuffer.Write(Content);
  end;
end;

{ TTExportSQL *****************************************************************}

procedure TTExportSQL.BeforeExecute();
var
  CycleProtection: Integer;
  DBObject: TSDBObject;
  I: Integer;
  J: Integer;
  K: Integer;
  NewIndex: Integer;
begin
  inherited;

  I := 0; CycleProtection := Items.Count - 1;
  while (I < Items.Count) do
  begin
    NewIndex := I;

    if ((Items[I] is TDBObjectItem) and Assigned(TDBObjectItem(Items[I]).DBObject.Dependencies)) then
      for J := 0 to TDBObjectItem(Items[I]).DBObject.Dependencies.Count - 1 do
      begin
        DBObject := TDBObjectItem(Items[I]).DBObject.Dependencies[J].DBObject;
        for K := I to Items.Count - 1 do
          if ((K <> I) and (Items[K] is TDBObjectItem)
            and (TDBObjectItem(Items[K]).DBObject = DBObject)) then
              NewIndex := Max(NewIndex, K);
      end;

    if ((NewIndex > I) and (CycleProtection > 0)) then
    begin
      Items.Move(I, NewIndex);
      Dec(CycleProtection);
    end
    else
    begin
      Inc(I);
      CycleProtection := Items.Count - I - 1;
    end;
  end;
end;

constructor TTExportSQL.Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
begin
  inherited;

  CreateDatabaseStmts := False;
  DisableKeys := False;
  DropStmts := False;
  UseDatabaseStmts := True;
end;

procedure TTExportSQL.ExecuteDatabaseHeader(const Database: TSDatabase);
var
  Content: string;
begin
  if (Assigned(Database)) then
  begin
    Content := '';

    if (UseDatabaseStmts or CreateDatabaseStmts) then
    begin
      Content := Content + #13#10;

      if (CreateDatabaseStmts) then
        Content := Content + Database.GetSourceEx(DropStmts);

      Content := Content + Database.SQLUse();
    end;

    WriteContent(Content);
  end;
end;

procedure TTExportSQL.ExecuteEvent(const Event: TSEvent);
var
  Content: string;
begin
  Content := #13#10;
  Content := Content + '#' + #13#10;
  Content := Content + '# Source for event "' + Event.Name + '"' + #13#10;
  Content := Content + '#' + #13#10;
  Content := Content + #13#10;
  Content := Content + Event.GetSourceEx(DropStmts, False);

  WriteContent(Content);
end;

procedure TTExportSQL.ExecuteFooter();
var
  Content: string;
begin
  Content := '';

  if (DisableKeys and (Session.ServerVersion >= 40014)) then
  begin
    Content := Content + '/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;' + #13#10;
    Content := Content + '/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;' + #13#10;
  end;
  if (Assigned(Session.VariableByName('SQL_NOTES')) and (Session.ServerVersion >= 40111)) then
    Content := Content + '/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;' + #13#10;
  if (Assigned(Session.VariableByName('SQL_MODE')) and (Session.ServerVersion >= 40101)) then
    Content := Content + '/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;' + #13#10;
  if (Assigned(Session.VariableByName('TIME_ZONE')) and (Session.VariableByName('TIME_ZONE').Value <> 'SYSTEM') and (Session.ServerVersion >= 40103)) then
    Content := Content + '/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;' + #13#10;
  if ((CodePage <> CP_UNICODE) and (Session.CodePageToCharset(CodePage) <> '') and (Session.ServerVersion >= 40101)) then
  begin
    Content := Content + '/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;' + #13#10;
    Content := Content + '/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;' + #13#10;
    Content := Content + '/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;' + #13#10;
  end;

  WriteContent(#13#10 + Content);
end;

procedure TTExportSQL.ExecuteHeader();
var
  Content: string;
begin
  DoFileCreate(Filename);

  Content := Content + '# Host: ' + Session.Host;
  if (Session.Port <> MYSQL_PORT) then
    Content := Content + ':' + IntToStr(Session.Port);
  Content := Content + '  (Version: ' + Session.ServerVersionStr + ')' + #13#10;
  Content := Content + '# Date: ' + MySQLDB.DateTimeToStr(Now(), Session.FormatSettings) + #13#10;
  Content := Content + '# Generator: ' + LoadStr(1000) + ' ' + Preferences.VersionStr + #13#10;
  Content := Content + #13#10;

  if ((CodePage <> CP_UNICODE) and (Session.CodePageToCharset(CodePage) <> '') and (Session.ServerVersion >= 40101)) then
  begin
    Content := Content + '/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;' + #13#10;
    Content := Content + '/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;' + #13#10;
    Content := Content + '/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;' + #13#10;
    Content := Content + '/*!40101 SET NAMES ' + Session.CodePageToCharset(CodePage) + ' */;' + #13#10;
  end;
  if (Assigned(Session.VariableByName('TIME_ZONE')) and (Session.VariableByName('TIME_ZONE').Value <> 'SYSTEM')) then
  begin
    Content := Content + '/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;' + #13#10;
    Content := Content + '/*!40103 SET TIME_ZONE=' + SQLEscape(Session.VariableByName('TIME_ZONE').Value) + ' */;' + #13#10;
  end;
  if (Assigned(Session.VariableByName('SQL_MODE')) and (Session.ServerVersion >= 40101)) then
  begin
    Content := Content + '/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE */;' + #13#10;
    Content := Content + '/*!40101 SET SQL_MODE=' + SQLEscape(Session.VariableByName('SQL_MODE').Value) + ' */;' + #13#10;
  end;
  if (Assigned(Session.VariableByName('SQL_NOTES'))) then
  begin
    Content := Content + '/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES */;' + #13#10;
    Content := Content + '/*!40103 SET SQL_NOTES=' + SQLEscape(Session.VariableByName('SQL_NOTES').Value) + ' */;' + #13#10;
  end;
  if (DisableKeys and (Session.ServerVersion >= 40014)) then
  begin
    Content := Content + '/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS */;' + #13#10;
    Content := Content + '/*!40014 SET UNIQUE_CHECKS=0 */;' + #13#10;
    Content := Content + '/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS */;' + #13#10;
    Content := Content + '/*!40014 SET FOREIGN_KEY_CHECKS=0 */;' + #13#10;
  end;

  WriteContent(Content);
end;

procedure TTExportSQL.ExecuteRoutine(const Routine: TSRoutine);
var
  Content: string;
begin
  Content := #13#10;
  if (Routine is TSProcedure) then
  begin
    Content := Content + '#' + #13#10;
    Content := Content + '# Source for procedure "' + Routine.Name + '"' + #13#10;
    Content := Content + '#' + #13#10;
  end
  else if (Routine is TSFunction) then
  begin
    Content := Content + '#' + #13#10;
    Content := Content + '# Source for function "' + Routine.Name + '"' + #13#10;
    Content := Content + '#' + #13#10;
  end;
  Content := Content + #13#10;
  Content := Content + Routine.GetSourceEx(DropStmts, False);

  WriteContent(Content);
end;

procedure TTExportSQL.ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  Content: string;
begin
  if (SQLInsertPacketLen > 0) then
  begin
    WriteContent(SQLInsertPostfix);
    SQLInsertPacketLen := 0;
  end;

  if (Assigned(Table) and Data) then
  begin
    Content := '';

    if (DisableKeys and (Table is TSBaseTable) and TSBaseTable(Table).Engine.IsMyISAM) then
      Content := Content + '/*!40000 ALTER TABLE ' + Session.EscapeIdentifier(Table.Name) + ' ENABLE KEYS */;' + #13#10;

    if (Content <> '') then
      WriteContent(Content);
  end;
end;

procedure TTExportSQL.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  Content: string;
  I: Integer;
begin
  Content := '';

  if (Structure and Assigned(Table)) then
  begin
    if (Table is TSBaseTable) then
    begin
      Content := Content + #13#10;
      Content := Content + '#' + #13#10;
      Content := Content + '# Source for table "' + Table.Name + '"' + #13#10;
      Content := Content + '#' + #13#10;
    end
    else if (Table is TSView) then
    begin
      Content := Content + #13#10;
      Content := Content + '#' + #13#10;
      Content := Content + '# Source for view "' + Table.Name + '"' + #13#10;
      Content := Content + '#' + #13#10;
    end;
    Content := Content + '' + #13#10;

    Content := Content + Table.GetSourceEx(DropStmts, False);
  end;

  if (Assigned(Table) and Assigned(DataSet)) then
  begin
    Content := Content + #13#10;
    Content := Content + '#' + #13#10;
    Content := Content + '# Data for table "' + Table.Name + '"' + #13#10;
    Content := Content + '#' + #13#10;
    Content := Content + #13#10;

    if (DisableKeys and (Table is TSBaseTable) and TSBaseTable(Table).Engine.IsMyISAM) then
      Content := Content + '/*!40000 ALTER TABLE ' + Session.EscapeIdentifier(Table.Name) + ' DISABLE KEYS */;' + #13#10;
  end;

  if (Content <> '') then
    WriteContent(Content);


  if (Data and Assigned(Table)) then
  begin
    if (ReplaceData) then
      SQLInsertPrefix := 'REPLACE INTO '
    else
      SQLInsertPrefix := 'INSERT INTO ';

    SQLInsertPrefix := SQLInsertPrefix + Session.EscapeIdentifier(Table.Name);

    if (not Structure) then
    begin
      SQLInsertPrefix := SQLInsertPrefix + ' (';
      for I := 0 to Length(Fields) - 1 do
      begin
        if (I > 0) then SQLInsertPrefix := SQLInsertPrefix + ',';
        SQLInsertPrefix := SQLInsertPrefix + Session.EscapeIdentifier(Fields[I].FieldName);
      end;
      SQLInsertPrefix := SQLInsertPrefix + ')';
    end;

    SQLInsertPrefix := SQLInsertPrefix + ' VALUES ';
    SQLInsertPrefixPacketLen := SizeOf(COM_QUERY) + WideCharToAnsiChar(Session.CodePage, PChar(SQLInsertPrefix), Length(SQLInsertPrefix), nil, 0);

    SQLInsertPostfix := ';' + #13#10;
    SQLInsertPrefixPacketLen := WideCharToAnsiChar(Session.CodePage, PChar(SQLInsertPostfix), Length(SQLInsertPostfix), nil, 0);

    SQLInsertPacketLen := 0;
  end;
end;

procedure TTExportSQL.ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  I: Integer;
  Values: string;
  ValuesPacketLen: Integer;
begin
  Values := '(';
  for I := 0 to Length(Fields) - 1 do
  begin
    if (I > 0) then Values := Values + ',';
    Values := Values + DataSet.SQLFieldValue(Fields[I]);
  end;
  Values := Values + ')';

  ValuesPacketLen := WideCharToAnsiChar(Session.CodePage, PChar(Values), Length(Values), nil, 0);

  if ((SQLInsertPacketLen > 0) and (SQLInsertPacketLen + ValuesPacketLen + SQLInsertPostfixPacketLen >= SQLPacketSize)) then
  begin
    WriteContent(SQLInsertPostfix);
    SQLInsertPacketLen := 0;
  end;

  if (SQLInsertPacketLen = 0) then
  begin
    WriteContent(SQLInsertPrefix);
    Inc(SQLInsertPacketLen, SQLInsertPrefixPacketLen);
  end
  else
  begin
    WriteContent(',');
    Inc(SQLInsertPacketLen, 1);
  end;

  WriteContent(Values);
  Inc(SQLInsertPacketLen, ValuesPacketLen);
end;

procedure TTExportSQL.ExecuteTrigger(const Trigger: TSTrigger);
var
  Content: string;
begin
  Content := #13#10;
  Content := Content + '#' + #13#10;
  Content := Content + '# Source for trigger "' + Trigger.Name + '"' + #13#10;
  Content := Content + '#' + #13#10;
  Content := Content + #13#10;
  Content := Content + Trigger.GetSourceEx(DropStmts, False);

  WriteContent(Content);
end;

function TTExportSQL.FileCreate(const Filename: TFileName; out Error: TTool.TError): Boolean;
var
  Size: DWord;
begin
  Result := inherited FileCreate(Filename, Error);

  if (Result) then
  begin
    case (CodePage) of
      CP_UTF8: Result := WriteFile(Handle, BOM_UTF8^, Length(BOM_UTF8), Size, nil) and (Integer(Size) = Length(BOM_UTF8));
      CP_UNICODE: Result := WriteFile(Handle, BOM_UNICODE_LE^, Length(BOM_UNICODE_LE), Size, nil) and (Integer(Size) = Length(BOM_UNICODE_LE));
    end;

    if (not Result) then
      Error := SysError();
  end;
end;

{ TTExportText ****************************************************************}

procedure TTExportText.AfterExecute();
begin
  if (Assigned(Zip)) then
    Zip.Free();

  inherited;
end;

procedure TTExportText.BeforeExecute();
begin
  inherited;

  if (Items.Count > 1) then
  begin
    Zip := TZipFile.Create();

    while ((Success <> daAbort) and (Zip.Mode <> zmWrite)) do
      try
        Zip.Open(Filename, zmWrite);
      except
        on E: EZipException do
          DoError(ZipError(Zip, E.Message), nil, True);
      end;
  end;
end;

constructor TTExportText.Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
begin
  inherited;

  Delimiter := ',';
  Quoter := '"';
  QuoteStringValues := True;
  QuoteValues := False;
  Zip := nil;
end;

destructor TTExportText.Destroy();
begin
  SetLength(DestinationFields, 0);
  SetLength(Fields, 0);
  SetLength(TableFields, 0);

  inherited;
end;

procedure TTExportText.ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
  CloseFile();

  if (Items.Count > 1) then
  begin
    if (Success = daSuccess) then
      try
        Zip.Add(TempFilename, Table.Name + '.csv');
      except
        on E: EZipException do
          DoError(ZipError(Zip, E.Message), nil, False);
      end;
    DeleteFile(TempFilename);
  end;
end;

procedure TTExportText.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  Content: string;
  I: Integer;
  Value: string;
begin
  if (Items.Count = 1) then
    DoFileCreate(Filename)
  else
  begin
    TempFilename := GetTempFileName();
    DoFileCreate(TempFilename);
  end;

  if ((Success = daSuccess) and Structure) then
  begin
    Content := '';

    for I := 0 to Length(Fields) - 1 do
    begin
      if (I > 0) then Content := Content + Delimiter;

      if (not Assigned(Table)) then
        Value := Fields[I].DisplayName
      else if (Length(DestinationFields) > 0) then
        Value := DestinationFields[I].Name
      else
        Value := Table.Fields[I].Name;

      if (QuoteValues or QuoteStringValues) then
        Content := Content + Quoter + Value + Quoter
      else
        Content := Content + Value;
    end;

    WriteContent(Content + #13#10);
  end;
end;

procedure TTExportText.ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  Content: string;
  I: Integer;
begin
  Content := '';
  for I := 0 to Length(Fields) - 1 do
  begin
    if (I > 0) then Content := Content + Delimiter;
    if (not Assigned(DataSet.LibRow^[Fields[I].FieldNo - 1])) then
      // NULL values are empty in MS Text files
    else if (BitField(Fields[I])) then
      Content := Content + CSVEscape(UInt64ToStr(Fields[I].AsLargeInt), Quoter, QuoteValues)
    else if (Fields[I].DataType in BinaryDataTypes) then
      Content := Content + CSVEscape(DataSet.LibRow^[Fields[I].FieldNo - 1], DataSet.LibLengths^[Fields[I].FieldNo - 1], Quoter, QuoteStringValues)
    else
      Content := Content + CSVEscape(DataSet.GetAsString(Fields[I]), Quoter, ((Fields[I].DataType in NotQuotedDataTypes)) and QuoteValues or not (Fields[I].DataType in NotQuotedDataTypes) and QuoteStringValues);
  end;
  WriteContent(Content + #13#10);
end;

function TTExportText.FileCreate(const Filename: TFileName; out Error: TTool.TError): Boolean;
var
  Size: DWord;
begin
  Result := inherited FileCreate(Filename, Error);

  if (Result) then
  begin
    case (CodePage) of
      CP_UTF8: Result := WriteFile(Handle, BOM_UTF8^, Length(BOM_UTF8), Size, nil) and (Integer(Size) = Length(BOM_UTF8));
      CP_UNICODE: Result := WriteFile(Handle, BOM_UNICODE_LE^, Length(BOM_UNICODE_LE), Size, nil) and (Integer(Size) = Length(BOM_UNICODE_LE));
    end;

    if (not Result) then
      Error := SysError();
  end;
end;

{ TTExportUML *****************************************************************}

procedure TTExportUML.ExecuteHeader();
begin
  DoFileCreate(Filename);
end;

{ TTExportHTML ****************************************************************}

constructor TTExportHTML.Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
begin
  inherited;

  TextContent := False;
  NULLText := True;
  RowBackground := True;

  Font := TFont.Create();
  Font.Name := Preferences.GridFontName;
  Font.Style := Preferences.GridFontStyle;
  Font.Charset := Preferences.GridFontCharset;
  Font.Color := Preferences.GridFontColor;
  Font.Size := Preferences.GridFontSize;

  SQLFont := TFont.Create();
  SQLFont.Name := Preferences.SQLFontName;
  SQLFont.Style := Preferences.SQLFontStyle;
  SQLFont.Charset := Preferences.SQLFontCharset;
  SQLFont.Color := Preferences.SQLFontColor;
  SQLFont.Size := Preferences.SQLFontSize;
end;

destructor TTExportHTML.Destroy();
begin
  Font.Free();
  SQLFont.Free();

  inherited;
end;

function TTExportHTML.EscapeSQL(const SQL: string): string;
begin
  Result := '<code>' + HTMLEscape(SQL) + '</code>' + #13#10;
end;

procedure TTExportHTML.ExecuteDatabaseHeader(const Database: TSDatabase);
begin
  if (Assigned(Database)) then
    WriteContent('<h1 class="DatabaseTitle">' + ReplaceStr(Preferences.LoadStr(38), '&', '') + ': ' + HTMLEscape(Database.Name) + '</h1>' + #13#10);
end;

procedure TTExportHTML.ExecuteEvent(const Event: TSEvent);
var
  Content: string;
begin
  Content := '<h2>' + Preferences.LoadStr(812) + ': ' + HTMLEscape(Event.Name) + '</h2>' + #13#10;

  Content := Content + EscapeSQL(Event.Source);

  WriteContent(Content);
end;

procedure TTExportHTML.ExecuteFooter();
var
  Content: string;
begin
  Content := '';
  Content := Content + '</body>' + #13#10;
  Content := Content + '</html>' + #13#10;

  WriteContent(Content);

  inherited;
end;

procedure TTExportHTML.ExecuteHeader();

  function ColorToHTML(AColor: TColor): string;
  var
    RGBColor: longint;
    RGBValue: byte;
  const
    Digits: array[0..15] of Char = '0123456789ABCDEF';
  begin
    RGBColor := ColorToRGB(AColor);
    Result := '#000000';
    RGBValue := GetRValue(RGBColor);
    if RGBValue > 0 then
    begin
      Result[2] := Digits[RGBValue shr  4];
      Result[3] := Digits[RGBValue and 15];
    end;
    RGBValue := GetGValue(RGBColor);
    if RGBValue > 0 then
    begin
      Result[4] := Digits[RGBValue shr  4];
      Result[5] := Digits[RGBValue and 15];
    end;
    RGBValue := GetBValue(RGBColor);
    if RGBValue > 0 then
    begin
      Result[6] := Digits[RGBValue shr  4];
      Result[7] := Digits[RGBValue and 15];
    end;
  end;

  function AttriToCSS(Attri: TSynHighlighterAttributes): string;
  begin
    Result := '{';
    if Attri.Foreground <> clNone then
      Result := Result + 'color: ' + ColorToHTML(Attri.Foreground) + '; ';
    if fsBold in Attri.Style then
      Result := Result + 'font-weight: bold; ';
    if fsItalic in Attri.Style then
      Result := Result + 'font-style: italic; ';
    if fsUnderline in Attri.Style then
      Result := Result + 'text-decoration: underline; ';
    if fsStrikeOut in Attri.Style then
      Result := Result + 'text-decoration: line-through; ';
    Result := Trim(Result) + '}';
  end;

var
  Content: string;
  Title: string;
begin
  inherited;

  Title := ExtractFileName(Filename);
  if (Pos('.', Title) > 0) then
  begin
    while (Title[Length(Title)] <> '.') do Delete(Title, Length(Title), 1);
    Delete(Title, Length(Title), 1);
  end;

  Content := '';
  Content := Content + '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"' + #13#10;
  Content := Content + ' "http://www.w3.org/TR/html4/strict.dtd">' + #13#10;
  Content := Content + '<html>' + #13#10;
  Content := Content + '<head>' + #13#10;
  Content := Content + #9 + '<title>' + HTMLEscape(Title) + '</title>' + #13#10;
  if (UMLEncoding(CodePage) <> '') then
    Content := Content + #9 + '<meta http-equiv="Content-Type" content="text/html; charset=' + UMLEncoding(CodePage) + '">' + #13#10;
  Content := Content + #9 + '<meta name="date" content="' + GetUTCDateTime(Now()) + '">' + #13#10;
  Content := Content + #9 + '<meta name="generator" content="' + LoadStr(1000) + ' ' + Preferences.VersionStr + '">' + #13#10;
  Content := Content + #9 + '<style type="text/css"><!--' + #13#10;
  Content := Content + #9#9 + 'body {font-family: Arial,Helvetica,sans-serif; font-size: ' + IntToStr(-Font.Height) + 'px;}' + #13#10;
  Content := Content + #9#9 + 'h1 {font-size: ' + IntToStr(-Font.Height + 6) + 'px; text-decoration: bold;}' + #13#10;
  Content := Content + #9#9 + 'h2 {font-size: ' + IntToStr(-Font.Height + 4) + 'px; text-decoration: bold;}' + #13#10;
  Content := Content + #9#9 + 'h3 {font-size: ' + IntToStr(-Font.Height + 2) + 'px; text-decoration: bold;}' + #13#10;
  Content := Content + #9#9 + 'th,' + #13#10;
  Content := Content + #9#9 + 'td {font-size: ' + IntToStr(-Font.Height) + 'px; border-color: #000000; border-style: solid; border-width: 1px; padding: 1px; font-weight: normal;}' + #13#10;
  Content := Content + #9#9 + 'code {font-size: ' + IntToStr(-SQLFont.Height) + 'px;}' + #13#10;
//  Content := Content + #9#9 + 'code.sql1-reservedword ' + AttriToCSS(MainHighlighter.KeyAttri) + #13#10;
//  Content := Content + #9#9 + 'code.sql1-number ' + AttriToCSS(MainHighlighter.NumberAttri) + #13#10;
//  Content := Content + #9#9 + 'code.sql1-symbol ' + AttriToCSS(MainHighlighter.SymbolAttri) + #13#10;
  Content := Content + #9#9 + '.TableObject {border-collapse: collapse; border-color: #000000; font-family: ' + HTMLEscape(Font.Name) + '}' + #13#10;
  Content := Content + #9#9 + '.TableData {border-collapse: collapse; border-color: #000000; font-family: ' + HTMLEscape(Font.Name) + '}' + #13#10;
  Content := Content + #9#9 + '.TableHeader {border-color: #000000; text-decoration: bold; background-color: #e0e0e0;}' + #13#10;
  Content := Content + #9#9 + '.StructureHeader {padding-left: 5px; text-align: left; border-color: #000000; text-decoration: bold;}' + #13#10;
  Content := Content + #9#9 + '.Structure {text-align: left; border-color: #aaaaaa;}' + #13#10;
  Content := Content + #9#9 + '.odd {}' + #13#10;
  if (RowBackground) then
    Content := Content + #9#9 + '.even {background-color: #f0f0f0;}' + #13#10
  else
    Content := Content + #9#9 + '.even {}' + #13#10;
  Content := Content + #9#9 + '.DataHeader {padding-left: 5px; text-align: left; border-color: #000000; background-color: #e0e0e0;}' + #13#10;
  Content := Content + #9#9 + '.Null {color: #999999;}' + #13#10;
  Content := Content + #9#9 + '.PrimaryKey {font-weight: bold;}' + #13#10;
  Content := Content + #9#9 + '.RightAlign {text-align: right;}' + #13#10;
  Content := Content + #9 + '--></style>' + #13#10;
  Content := Content + '</head>' + #13#10;
  Content := Content + '<body>' + #13#10;

  WriteContent(Content);
end;

procedure TTExportHTML.ExecuteRoutine(const Routine: TSRoutine);
var
  Content: string;
begin
  if (Routine is TSProcedure) then
    Content := '<h2>' + Preferences.LoadStr(768) + ': ' + HTMLEscape(Routine.Name) + '</h2>' + #13#10
  else
    Content := '<h2>' + Preferences.LoadStr(769) + ': ' + HTMLEscape(Routine.Name) + '</h2>' + #13#10;

  Content := Content + EscapeSQL(Routine.Source);

  WriteContent(Content);
end;

procedure TTExportHTML.ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
  if (Data) then
    WriteContent('</table><br style="page-break-after: always">' + #13#10);

  SetLength(CSS, 0);
  SetLength(FieldOfPrimaryIndex, 0);
end;

procedure TTExportHTML.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  ClassAttr: string;
  Content: string;
  FieldInfo: TFieldInfo;
  I: Integer;
  J: Integer;
  S: string;
  S2: string;
begin
  Content := '';

  if (Table is TSBaseTable) then
  begin
    Content := '<h2>' + ReplaceStr(Preferences.LoadStr(302), '&', '') + ': ' + HTMLEscape(Table.Name) + '</h2>' + #13#10;
    if (TSBaseTable(Table).Comment <> '') then
      Content := Content + '<p>' + ReplaceStr(Preferences.LoadStr(111), '&', '') + ': ' + HTMLEscape(TSBaseTable(Table).Comment) + '</p>' + #13#10;
  end
  else if (Table is TSView) then
    Content := '<h2>' + ReplaceStr(Preferences.LoadStr(738), '&', '') + ': ' + HTMLEscape(Table.Name) + '</h2>' + #13#10
  else if (Structure) then
    Content := Content + '<h2>' + ReplaceStr(Preferences.LoadStr(216), '&', '') + ':</h2>' + #13#10;

  if (Structure) then
    if (DataSet is TMySQLDataSet) then
    begin
      Content := Content + '<h2>' + ReplaceStr(Preferences.LoadStr(794), '&', '') + ':</h2>' + #13#10;
      Content := Content + EscapeSQL(DataSet.CommandText);
    end
    else
    begin
      if ((Table is TSBaseTable) and (TSBaseTable(Table).Keys.Count > 0)) then
      begin
        Content := Content + '<h3>' + Preferences.LoadStr(458) + ':</h3>' + #13#10;

        Content := Content + '<table border="0" cellspacing="0" summary="' + HTMLEscape(Table.Name) + '" class="TableObject">' + #13#10;
        Content := Content + #9 + '<tr class="TableHeader StructureHeader">';
        Content := Content + '<th>' + HTMLEscape(ReplaceStr(Preferences.LoadStr(35), '&', '')) + '</th>';
        Content := Content + '<th>' + HTMLEscape(Preferences.LoadStr(69)) + '</th>';
        Content := Content + '<th>' + HTMLEscape(ReplaceStr(Preferences.LoadStr(73), '&', '')) + '</th>';
        if (Session.ServerVersion >= 50503) then
          Content := Content + '<th>' + HTMLEscape(ReplaceStr(Preferences.LoadStr(111), '&', '')) + '</th>';
        Content := Content + '</tr>' + #13#10;
        for I := 0 to TSBaseTable(Table).Keys.Count - 1 do
        begin
          if (TSBaseTable(Table).Keys[I].Primary) then
            ClassAttr := ' class="PrimaryKey"'
          else
            ClassAttr := '';

          Content := Content + #9 + '<tr class="Structure">';
          Content := Content + '<td ' + ClassAttr + '>' + HTMLEscape(TSBaseTable(Table).Keys[I].Caption) + '</td>';
          S := '';
          for J := 0 to TSBaseTable(Table).Keys[I].Columns.Count - 1 do
            begin
              if (S <> '') then S := S + ', ';
              S := S + TSBaseTable(Table).Keys[I].Columns[J].Field.Name;
            end;
          Content := Content + '<td>' + HTMLEscape(S) + '</td>';
          if (TSBaseTable(Table).Keys[I].Unique) then
            Content := Content + '<td>unique</td>'
          else if (TSBaseTable(Table).Keys[I].Fulltext) then
            Content := Content + '<td>fulltext</td>'
          else
            Content := Content + '<td>&nbsp;</td>';
          if (Session.ServerVersion >= 50503) then
            Content := Content + '<td>' + HTMLEscape(TSBaseTable(Table).Keys[I].Comment) + '</td>';
          Content := Content + '</tr>' + #13#10;
        end;
        Content := Content + '</table><br>' + #13#10;
      end;

      Content := Content + '<h3>' + Preferences.LoadStr(253) + ':</h3>' + #13#10;

      Content := Content + '<table border="0" cellspacing="0" summary="' + HTMLEscape(Table.Name) + '" class="TableObject">' + #13#10;
      Content := Content + #9 + '<tr class="TableHeader StructureHeader">';
      Content := Content + '<th>' + HTMLEscape(ReplaceStr(Preferences.LoadStr(35), '&', '')) + '</th>';
      Content := Content + '<th>' + HTMLEscape(Preferences.LoadStr(69)) + '</th>';
      Content := Content + '<th>' + HTMLEscape(Preferences.LoadStr(71)) + '</th>';
      Content := Content + '<th>' + HTMLEscape(Preferences.LoadStr(72)) + '</th>';
      Content := Content + '<th>' + HTMLEscape(ReplaceStr(Preferences.LoadStr(73), '&', '')) + '</th>';
      if (Session.ServerVersion >= 40100) then
        Content := Content + '<th>' + HTMLEscape(ReplaceStr(Preferences.LoadStr(111), '&', '')) + '</th>';
      Content := Content + '</tr>' + #13#10;
      for I := 0 to Table.Fields.Count - 1 do
      begin
        if (Table.Fields[I].InPrimaryKey) then
          ClassAttr := ' class="PrimaryKey"'
        else
          ClassAttr := '';

        Content := Content + #9 + '<tr class="Structure">';
        Content := Content + '<td' + ClassAttr + '>' + HTMLEscape(Table.Fields[I].Name) + '</td>';
        Content := Content + '<td>' + HTMLEscape(Table.Fields[I].DBTypeStr()) + '</td>';
        if (Table.Fields[I].NullAllowed) then
          Content := Content + '<td>' + HTMLEscape(Preferences.LoadStr(74)) + '</td>'
        else
          Content := Content + '<td>' + HTMLEscape(Preferences.LoadStr(75)) + '</td>';
        if (Table.Fields[I].AutoIncrement) then
          Content := Content + '<td>&lt;auto_increment&gt;</td>'
        else if (Table.Fields[I].Default = 'NULL') then
          Content := Content + '<td class="Null">&lt;' + Preferences.LoadStr(71) + '&gt;</td>'
        else if (Table.Fields[I].Default = 'CURRENT_TIMESTAMP') then
          Content := Content + '<td>&lt;INSERT-TimeStamp&gt;</td>'
        else if (Table.Fields[I].Default <> '') then
          Content := Content + '<td>' + HTMLEscape(Table.Fields[I].UnescapeValue(Table.Fields[I].Default)) + '</td>'
        else
          Content := Content + '<td>&nbsp;</td>';
        S := '';
        if ((Table is TSBaseTable) and (Table.Fields[I].FieldType in TextFieldTypes)) then
        begin
          if ((Table.Fields[I].Charset <> '') and (Table.Fields[I].Charset <> TSBaseTable(Table).DefaultCharset)) then
            S := S + Table.Fields[I].Charset;
          if ((Table.Fields[I].Collation <> '') and (Table.Fields[I].Collation <> TSBaseTable(Table).Collation)) then
          begin
            if (S <> '') then S := S + ', ';
            S := S + Table.Fields[I].Collation;
          end;
        end;
        if (S <> '') then
          Content := Content + '<td>' + HTMLEscape(S) + '</td>'
        else
          Content := Content + '<td>&nbsp;</td>';
        if (Session.ServerVersion >= 40100) then
          if (TSBaseTableField(Table.Fields[I]).Comment <> '') then
            Content := Content + '<td>' + HTMLEscape(TSBaseTableField(Table.Fields[I]).Comment) + '</td>'
          else
            Content := Content + '<td>&nbsp;</td>';
        Content := Content + #9 + '</tr>' + #13#10;
      end;
      Content := Content + '</table><br>' + #13#10;

      if ((Table is TSBaseTable) and (TSBaseTable(Table).ForeignKeys.Count > 0)) then
      begin
        Content := Content + '<h3>' + Preferences.LoadStr(459) + ':</h3>' + #13#10;

        Content := Content + '<table border="0" cellspacing="0" summary="' + HTMLEscape(Table.Name) + '" class="TableObject">' + #13#10;
        Content := Content + #9 + '<tr class="TableHeader StructureHeader">';
        Content := Content + '<th>' + HTMLEscape(ReplaceStr(Preferences.LoadStr(35), '&', '')) + '</th>';
        Content := Content + '<th>' + HTMLEscape(Preferences.LoadStr(69)) + '</th>';
        Content := Content + '<th>' + HTMLEscape(Preferences.LoadStr(73)) + '</th>';
        Content := Content + '</tr>' + #13#10;
        for I := 0 to TSBaseTable(Table).ForeignKeys.Count - 1 do
        begin
          Content := Content + #9 + '<tr>';
          Content := Content + '<th>' + HTMLEscape(TSBaseTable(Table).ForeignKeys[I].Name) + '</th>';
          Content := Content + '<td>' + HTMLEscape(TSBaseTable(Table).ForeignKeys[I].DBTypeStr()) + '</td>';
          S := '';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtCascade) then S := 'cascade on delete';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtSetNull) then S := 'set NULL on delete';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtSetDefault) then S := 'set default on delete';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtNoAction) then S := 'no action on delete';
          S2 := '';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utCascade) then S2 := 'cascade on update';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utSetNull) then S2 := 'set NULL on update';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utSetDefault) then S2 := 'set default on update';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utNoAction) then S2 := 'no action on update';
          if (S <> '') and (S2 <> '') then S := S + ', ';
          S := S + S2;
          Content := Content + '<td>' + HTMLEscape(S) + '</td>';
          Content := Content + '</tr>' + #13#10;
        end;
        Content := Content + '</table><br>' + #13#10;
      end;
    end;

  if (Data) then
  begin
    if (Structure) then
      Content := Content + '<h3>' + Preferences.LoadStr(580) + ':</h3>' + #13#10;

    if (Assigned(Table)) then
      Content := Content + '<table border="0" cellspacing="0" summary="' + HTMLEscape(Table.Name) + '" class="TableData">' + #13#10
    else
      Content := Content + '<table border="0" cellspacing="0" class="TableData">' + #13#10;
    Content := Content + #9 + '<tr class="TableHeader">';

    SetLength(FieldOfPrimaryIndex, Length(Fields));
    for I := 0 to Length(Fields) - 1 do
    begin
      FieldOfPrimaryIndex[I] := Fields[I].IsIndexField;

      if (FieldOfPrimaryIndex[I]) then
        Content := Content + '<th class="DataHeader PrimaryKey">'
      else
        Content := Content + '<th class="DataHeader">';

      if (I < Length(DestinationFields)) then
        Content := Content + HTMLEscape(DestinationFields[I].Name) + '</th>'
      else
        Content := Content + HTMLEscape(Fields[I].DisplayName) + '</th>';
    end;
    Content := Content + '</tr>' + #13#10;


    SetLength(CSS, Length(Fields));
    for I := 0 to Length(Fields) - 1 do
    begin
      CSS[I] := '';
      if (FieldOfPrimaryIndex[I]) then
        CSS[I] := CSS[I] + ' PrimaryKey';
      if (Fields[I].Alignment = taRightJustify) then
        CSS[I] := CSS[I] + ' RightAlign';
      CSS[I] := Trim(CSS[I]);

      RowOdd := True;
    end;
  end;

  WriteContent(Content);
end;

procedure TTExportHTML.ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  Content: string;
  I: Integer;
  Value: string;
begin
  Content := '';

  if (RowOdd) then
    Content := Content + #9 + '<tr class="Data odd">'
  else
    Content := Content + #9 + '<tr class="Data even">';
  RowOdd := not RowOdd;

  for I := 0 to Length(Fields) - 1 do
    if (Fields[I].IsNull) then
      if (NULLText) then
        Content := Content + '<td class="Null">&lt;NULL&gt;</td>'
      else
        Content := Content + '<td class="Null">&nbsp;</td>'
    else
    begin
      if (DataSet.LibLengths^[I] = 0) then
        Value := '&nbsp;'
      else if (GeometryField(Fields[I])) then
        Value := '&lt;GEO&gt;'
      else if (not TextContent and (Fields[I].DataType = ftWideMemo)) then
        Value := '&lt;MEMO&gt;'
      else if (Fields[I].DataType = ftBytes) then
        Value := '&lt;BINARY&gt;'
      else if (Fields[I].DataType = ftBlob) then
        Value := '&lt;BLOB&gt;'
      else if (Fields[I].DataType in TextDataTypes) then
        Value := HTMLEscape(DataSet.GetAsString(Fields[I]))
      else
        Value := DataSet.GetAsString(Fields[I]);

      if (FieldOfPrimaryIndex[I]) then
        Content := Content + '<th class="' + CSS[I] + '">' + Value + '</th>'
      else
        Content := Content + '<td class="' + CSS[I] + '">' + Value + '</td>';
    end;

  Content := Content + '</tr>' + #13#10;

  WriteContent(Content);
end;

procedure TTExportHTML.ExecuteTrigger(const Trigger: TSTrigger);
var
  Content: string;
begin
  Content := '<h2>' + Preferences.LoadStr(788) + ': ' + HTMLEscape(Trigger.Name) + '</h2>' + #13#10;

  Content := Content + EscapeSQL(Trigger.Source);

  WriteContent(Content);
end;

{ TTExportXML *****************************************************************}

constructor TTExportXML.Create(const ASession: TSSession; const AFilename: TFileName; const ACodePage: Cardinal);
begin
  inherited;

  DatabaseNodeText := '';
  RootNodeText := '';
  TableNodeText := '';
end;

procedure TTExportXML.ExecuteDatabaseFooter(const Database: TSDatabase);
begin
  if (Assigned(Database)) then
    if (DatabaseNodeAttribute <> '') then
      WriteContent('</' + DatabaseNodeText + '>' + #13#10)
    else if (DatabaseNodeText <> '') then
      WriteContent('</' + SysUtils.LowerCase(XMLEscape(Database.Name)) + '>' + #13#10);
end;

procedure TTExportXML.ExecuteDatabaseHeader(const Database: TSDatabase);
begin
  if (Assigned(Database)) then
    if (DatabaseNodeAttribute <> '') then
      WriteContent('<' + DatabaseNodeText + ' ' + DatabaseNodeAttribute + '="' + XMLEscape(Database.Name) + '">' + #13#10)
    else if (DatabaseNodeText <> '') then
      WriteContent('<' + SysUtils.LowerCase(XMLEscape(Database.Name)) + '>' + #13#10);
end;

procedure TTExportXML.ExecuteFooter();
begin
  WriteContent('</' + RootNodeText + '>' + #13#10);
end;

procedure TTExportXML.ExecuteHeader();
begin
  DoFileCreate(FFilename);

  if (UMLEncoding(CodePage) = '') then
    WriteContent('<?xml version="1.0"?>' + #13#10)
  else
    WriteContent('<?xml version="1.0" encoding="' + UMLEncoding(CodePage) + '"?>' + #13#10);
  WriteContent('<' + RootNodeText + ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' + #13#10);
end;

procedure TTExportXML.ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
  if (Assigned(Table)) then
    if (TableNodeAttribute <> '') then
      WriteContent('</' + TableNodeText + '>' + #13#10)
    else if (TableNodeText <> '') then
      WriteContent('</' + SysUtils.LowerCase(XMLEscape(Table.Name)) + '>' + #13#10);
end;

procedure TTExportXML.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
  if (Assigned(Table)) then
    if (TableNodeAttribute <> '') then
      WriteContent('<' + TableNodeText + ' ' + TableNodeAttribute + '="' + XMLEscape(Table.Name) + '">' + #13#10)
    else if (TableNodeText <> '') then
      WriteContent('<' + SysUtils.LowerCase(XMLEscape(Table.Name)) + '>' + #13#10);
end;

procedure TTExportXML.ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  Content: string;
  I: Integer;
begin
  Content := #9 + '<' + RecordNodeText + '>' + #13#10;

  for I := 0 to Length(Fields) - 1 do
  begin
    if (FieldNodeAttribute = '') then
      if (Length(DestinationFields) > 0) then
        Content := Content + #9#9 + '<' + SysUtils.LowerCase(XMLEscape(DestinationFields[I].Name)) + ''
      else
        Content := Content + #9#9 + '<' + SysUtils.LowerCase(XMLEscape(Fields[I].DisplayName)) + ''
    else
      if (Length(DestinationFields) > 0) then
        Content := Content + #9#9 + '<' + FieldNodeText + ' ' + FieldNodeAttribute + '="' + XMLEscape(DestinationFields[I].Name) + '"'
      else
        Content := Content + #9#9 + '<' + FieldNodeText + ' ' + FieldNodeAttribute + '="' + XMLEscape(Fields[I].DisplayName) + '"';
    if (Fields[I].IsNull) then
      Content := Content + ' xsi:nil="true" />' + #13#10
    else
    begin
      if (Fields[I].DataType in TextDataTypes + BinaryDataTypes) then
        Content := Content + '>' + XMLEscape(DataSet.GetAsString(Fields[I]))
      else
        Content := Content + '>' + DataSet.GetAsString(Fields[I]);

      if (FieldNodeAttribute = '') then
        if (Length(DestinationFields) > 0) then
          Content := Content + '</' + SysUtils.LowerCase(XMLEscape(DestinationFields[I].Name)) + '>' + #13#10
        else
          Content := Content + '</' + SysUtils.LowerCase(XMLEscape(Fields[I].DisplayName)) + '>' + #13#10
      else
        Content := Content + '</' + FieldNodeText + '>' + #13#10;
    end;
  end;

  Content := Content + #9 + '</' + RecordNodeText + '>' + #13#10;

  WriteContent(Content);
end;

{ TTExportBaseODBC ************************************************************}

constructor TTExportBaseODBC.Create(const ASession: TSSession; const AHandle: SQLHDBC);
begin
  inherited Create(ASession);

  FHandle := AHandle;

  FStmt := SQL_NULL_HANDLE;
  TableName := '';
end;

procedure TTExportBaseODBC.ExecuteFooter();
begin
  if (FStmt <> SQL_NULL_HANDLE) then
    begin SQLFreeHandle(SQL_HANDLE_STMT, FStmt); FStmt := SQL_NULL_HANDLE; end;

  if (FHandle <> SQL_NULL_HANDLE) then
  begin
    SQLDisconnect(FHandle);
    SQLFreeHandle(SQL_HANDLE_DBC, FHandle); FHandle := SQL_NULL_HANDLE;
  end;

  inherited;
end;

procedure TTExportBaseODBC.ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  I: Integer;
begin
  TableName := '';

  for I := 0 to Length(Parameter) - 1 do
    FreeMem(Parameter[I].Buffer);
  SetLength(Parameter, 0);

  inherited;
end;

procedure TTExportBaseODBC.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  ColumnSize: SQLUINTEGER;
  Error: TTool.TError;
  I: Integer;
  J: Integer;
  SQL: string;
  ValueType: SQLSMALLINT;
  ParameterType: SQLSMALLINT;
begin
  if (not (Self is TTExportExcel)) then
  begin
    if (TableName = '') then
      TableName := Table.Name;

    SQL := 'CREATE TABLE "' + TableName + '" (';
    for I := 0 to Length(Fields) - 1 do
    begin
      if (I > 0) then SQL := SQL + ', ';
      SQL := SQL + '"' + Table.Fields[I].Name + '" ';

      if (Table.Fields[I].AutoIncrement and (Table.Fields[I].FieldType in [mfTinyInt, mfSmallInt, mfMediumInt, mfInt])) then
        SQL := SQL + 'COUNTER'
      else
        case (Table.Fields[I].FieldType) of
          mfBit:
            if ((Self is TTExportAccess) and (Table.Fields[I].Size = 1)) then
              SQL := SQL + 'BIT'
            else
              SQL := SQL + 'BINARY(' + IntToStr(Table.Fields[I].Size div 8) + ')';
          mfTinyInt:
            if (Table.Fields[I].Unsigned) then
              SQL := SQL + 'BYTE'
            else
              SQL := SQL + 'SMALLINT';
          mfSmallInt, mfYear:
            if (not Table.Fields[I].Unsigned) then
              SQL := SQL + 'SMALLINT'
            else
              SQL := SQL + 'INTEGER';
          mfMediumInt:
            SQL := SQL + 'INTEGER';
          mfInt:
            if (not Table.Fields[I].Unsigned) then
              SQL := SQL + 'INTEGER'
            else
              SQL := SQL + 'VARCHAR(10)';
          mfBigInt:
            SQL := SQL + 'VARCHAR(20)';
          mfFloat:
            SQL := SQL + 'REAL';
          mfDouble:
            SQL := SQL + 'FLOAT';
          mfDecimal:
            SQL := SQL + 'CURRENCY';
          mfDate:
            SQL := SQL + 'DATE';
          mfDateTime, mfTimeStamp:
            SQL := SQL + 'TIMESTAMP';
          mfTime:
            SQL := SQL + 'TIME';
          mfChar:
            SQL := SQL + 'CHAR(' + IntToStr(Table.Fields[I].Size) + ')';
          mfEnum, mfSet:
            SQL := SQL + 'VARCHAR';
          mfVarChar:
            if (Table.Fields[I].Size <= 255) then
              SQL := SQL + 'VARCHAR(' + IntToStr(Table.Fields[I].Size) + ')'
            else
              SQL := SQL + 'LONGTEXT';
          mfTinyText, mfText, mfMediumText, mfLongText:
            SQL := SQL + 'LONGTEXT';
          mfBinary:
            SQL := SQL + 'BINARY(' + IntToStr(Table.Fields[I].Size) + ')';
          mfVarBinary:
            if (Table.Fields[I].Size <= 255) then
              SQL := SQL + 'VARBINARY(' + IntToStr(Table.Fields[I].Size) + ')'
            else
              SQL := SQL + 'LONGBINARY';
          mfTinyBlob, mfBlob, mfMediumBlob, mfLongBlob,
          mfGeometry, mfPoint, mfLineString, mfPolygon, mfMultiPoint, mfMultiLineString, mfMultiPolygon, mfGeometryCollection:
            SQL := SQL + 'LONGBINARY';
          else
            raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [Table.Fields[I].Name, Ord(Table.Fields[I].FieldType)]);
        end;
      if (not Table.Fields[I].NullAllowed) then
        SQL := SQL + ' NOT NULL';
    end;
    if ((Table is TSBaseTable) and Assigned(TSBaseTable(Table).PrimaryKey)) then
    begin
      SQL := SQL + ', PRIMARY KEY (';
      for I := 0 to TSBaseTable(Table).PrimaryKey.Columns.Count - 1 do
      begin
        if (I > 0) then SQL := SQL + ',';
        SQL := SQL + '"' + TSBaseTable(Table).PrimaryKey.Columns[I].Field.Name + '"';
      end;
      SQL := SQL + ')';
    end;
    SQL := SQL + ')';

    if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, Handle, @FStmt))) then
      DoError(ODBCError(SQL_HANDLE_ENV, ODBCEnv), nil, False);

    while ((Success <> daAbort) and not SQL_SUCCEEDED(SQLExecDirect(Stmt, PSQLTCHAR(SQL), SQL_NTS))) do
    begin
      Error := ODBCError(SQL_HANDLE_STMT, Stmt);
      Error.ErrorMessage := Error.ErrorMessage + ' - ' + SQL;
      DoError(Error, nil, True);
    end;


    if (Table is TSBaseTable) then
      for I := 0 to TSBaseTable(Table).Keys.Count - 1 do
        if (not TSBaseTable(Table).Keys[I].Primary) then
        begin
          SQL := 'CREATE';
          if (TSBaseTable(Table).Keys[I].Unique) then
            SQL := SQL + ' UNIQUE';
          SQL := SQL + ' INDEX "' + TSBaseTable(Table).Keys[I].Name + '"';
          SQL := SQL + ' ON "' + Table.Name + '"';
          SQL := SQL + ' (';
          for J := 0 to TSBaseTable(Table).Keys[I].Columns.Count - 1 do
          begin
            if (J > 0) then SQL := SQL + ',';
            SQL := SQL + '"' + TSBaseTable(Table).Keys[I].Columns[J].Field.Name + '"';
          end;
          SQL := SQL + ');';

          // Execute silent, since some ODBC drivers doesn't support keys
          // and the user should know that...
          SQLExecDirect(Stmt, PSQLTCHAR(SQL), SQL_NTS);
        end;
  end;

  SetLength(Parameter, Length(Fields));

  for I := 0 to Length(Fields) - 1 do
  begin
    if (BitField(Fields[I])) then
      begin
        ValueType := SQL_C_ULONG;
        ParameterType := SQL_INTEGER;
        ColumnSize := 8;
        Parameter[I].BufferSize := Fields[I].DataSize;
      end
    else
      case (Fields[I].DataType) of
        ftString:
          begin
            ValueType := SQL_C_BINARY;
            ParameterType := SQL_BINARY;
            ColumnSize := Fields[I].Size;
            Parameter[I].BufferSize := ColumnSize;
          end;
        ftShortInt,
        ftByte,
        ftSmallInt,
        ftWord,
        ftInteger,
        ftLongWord,
        ftLargeint:
          begin
            ValueType := SQL_C_CHAR;
            ParameterType := SQL_CHAR;
            ColumnSize := 100;
            Parameter[I].BufferSize := ColumnSize;
          end;
        ftSingle,
        ftFloat,
        ftExtended:
          begin
            ValueType := SQL_C_CHAR;
            ParameterType := SQL_C_DOUBLE;
            ColumnSize := 100;
            Parameter[I].BufferSize := ColumnSize;
          end;
        ftTimestamp:
          begin
            ValueType := SQL_C_CHAR;
            ParameterType := SQL_CHAR;
            ColumnSize := 100;
            Parameter[I].BufferSize := ColumnSize;
          end;
        ftDate:
          begin
            ValueType := SQL_C_CHAR;
            ParameterType := SQL_TYPE_DATE;
            ColumnSize := 10; // 'yyyy-mm-dd'
            Parameter[I].BufferSize := ColumnSize;
          end;
        ftDateTime:
          begin
            ValueType := SQL_C_CHAR;
            ParameterType := SQL_TYPE_TIMESTAMP;
            ColumnSize := 19; // 'yyyy-mm-dd hh:hh:ss'
            Parameter[I].BufferSize := ColumnSize;
          end;
        ftTime:
          begin
            ValueType := SQL_C_CHAR;
            ParameterType := -154; // SQL_SS_TIME2
            ColumnSize := 8; // 'hh:mm:ss'
            Parameter[I].BufferSize := ColumnSize;
          end;
        ftWideString:
          begin
            if (Fields[I].Size < 256) then
            begin
              ValueType := SQL_C_WCHAR;
              ParameterType := SQL_WCHAR;
              ColumnSize := Fields[I].Size;
              Parameter[I].BufferSize := ColumnSize * SizeOf(Char);
            end
            else
            begin
              ValueType := SQL_C_WCHAR;
              ParameterType := SQL_WLONGVARCHAR;
              ColumnSize := Fields[I].Size;
              Parameter[I].BufferSize := ODBCDataSize;
            end;
          end;
        ftWideMemo:
          begin
            ValueType := SQL_C_WCHAR;
            ParameterType := SQL_WLONGVARCHAR;
            ColumnSize := Fields[I].Size;
            Parameter[I].BufferSize := ODBCDataSize;
          end;
        ftBlob:
          begin
            ValueType := SQL_C_BINARY;
            ParameterType := SQL_LONGVARBINARY;
            ColumnSize := Fields[I].Size;
            Parameter[I].BufferSize := ODBCDataSize;
          end;
        else
          raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [Fields[I].DisplayName, Ord(Fields[I].DataType)]);
      end;
    GetMem(Parameter[I].Buffer, Parameter[I].BufferSize);

    if ((Success = daSuccess) and not SQL_SUCCEEDED(SQLBindParameter(Stmt, 1 + I, SQL_PARAM_INPUT, ValueType, ParameterType,
      ColumnSize, 0, Parameter[I].Buffer, Parameter[I].BufferSize, @Parameter[I].Size))) then
    begin
      Error := ODBCError(SQL_HANDLE_STMT, Stmt);
      Error.ErrorMessage := Error.ErrorMessage;
      DoError(Error, nil, False);
    end;
  end;

  SQL := 'INSERT INTO "' + TableName + '" VALUES (';
  for I := 0 to Length(Fields) - 1 do
  begin
    if (I > 0) then SQL := SQL + ',';
    SQL := SQL + '?';
  end;
  SQL := SQL + ')';

  if ((Success = daSuccess) and not SQL_SUCCEEDED(SQLPrepare(Stmt, PSQLTCHAR(SQL), SQL_NTS))) then
  begin
    Error := ODBCError(SQL_HANDLE_STMT, Stmt);
    Error.ErrorMessage := Error.ErrorMessage + ' - ' + SQL;
    DoError(Error, nil, False);
  end;
end;

procedure TTExportBaseODBC.ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  BlockSize: Integer;
  Buffer: SQLPOINTER;
  DateTime: TDateTime;
  Error: TTool.TError;
  I: Integer;
  Index: Integer;
  L: LargeInt;
  ReturnCode: SQLRETURN;
  S: string;
  Size: Integer;
begin
  for I := 0 to Length(Fields) - 1 do
    if (Fields[I].IsNull) then
      Parameter[I].Size := SQL_NULL_DATA
    else if (BitField(Fields[I])) then
      begin
        L := Fields[I].AsLargeInt;
        Parameter[I].Size := SizeOf(L);
        MoveMemory(Parameter[I].Buffer, @L, Parameter[I].Size);
      end
    else
      case (Fields[I].DataType) of
        ftString:
          begin
            Parameter[I].Size := Min(Parameter[I].BufferSize, DataSet.LibLengths^[I]);
            MoveMemory(Parameter[I].Buffer, DataSet.LibRow^[I], Parameter[I].Size);
          end;
        ftShortInt,
        ftByte,
        ftSmallInt,
        ftWord,
        ftInteger,
        ftLongWord,
        ftLargeint,
        ftSingle,
        ftFloat,
        ftExtended,
        ftTimestamp:
          begin
            Parameter[I].Size := Min(Parameter[I].BufferSize, DataSet.LibLengths^[I]);
            MoveMemory(Parameter[I].Buffer, DataSet.LibRow^[I], Parameter[I].Size);
          end;
        ftDate,
        ftTime,
        ftDateTime:
          begin
            SetString(S, DataSet.LibRow^[I], DataSet.LibLengths^[I]);
            if (not TryStrToDateTime(S, DateTime)) then // Dedect MySQL invalid dates like '0000-00-00' or '2012-02-30'
              Parameter[I].Size := SQL_NULL_DATA        // Handle them as NULL values
            else
            begin
              Parameter[I].Size := Min(Parameter[I].BufferSize, DataSet.LibLengths^[I]);
              MoveMemory(Parameter[I].Buffer, DataSet.LibRow^[I], Parameter[I].Size);
            end;
          end;
        ftWideString,
        ftWideMemo:
          begin
            Size := AnsiCharToWideChar(Session.CodePage, DataSet.LibRow^[I], DataSet.LibLengths^[I], nil, 0) * SizeOf(Char);
            if (Size < Parameter[I].BufferSize div SizeOf(Char)) then
              Parameter[I].Size := AnsiCharToWideChar(Session.CodePage, DataSet.LibRow^[I], DataSet.LibLengths^[I], Parameter[I].Buffer, Parameter[I].BufferSize div SizeOf(Char)) * SizeOf(Char)
            else
              Parameter[I].Size := SQL_LEN_DATA_AT_EXEC(Size * SizeOf(Char));
          end;
        ftBlob:
          if (DataSet.LibLengths^[I] <= Parameter[I].BufferSize) then
          begin
            Parameter[I].Size := DataSet.LibLengths^[I];
            MoveMemory(Parameter[I].Buffer, DataSet.LibRow^[I], Parameter[I].Size);
          end
          else
            Parameter[I].Size := SQL_LEN_DATA_AT_EXEC(DataSet.LibLengths^[I]);
        else
          raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [Fields[I].DisplayName, Ord(Fields[I].DataType)]);
      end;

  repeat
    ReturnCode := SQLExecute(Stmt);
    if (not SQL_SUCCEEDED(ReturnCode) and (ReturnCode <> SQL_NEED_DATA)) then
    begin
      Error := ODBCError(SQL_HANDLE_STMT, Stmt);
      Error.ErrorMessage := Error.ErrorMessage;
      DoError(Error, nil, True);
    end;
  until ((Success = daAbort) or SQL_SUCCEEDED(ReturnCode) or (ReturnCode = SQL_NEED_DATA));

  while ((Success = daSuccess) and (ReturnCode = SQL_NEED_DATA)) do
  begin
    ReturnCode := SQLParamData(Stmt, @Buffer);
    if (ReturnCode = SQL_NEED_DATA) then
      for I := 0 to Length(Fields) - 1 do
        if (Buffer = Parameter[I].Buffer) then
        begin
          case (Fields[I].DataType) of
            ftWideString,
            ftWideMemo:
              begin
                S := DataSet.GetAsString(Fields[I]);
                Size := Length(S) * SizeOf(Char);
                Index := 0;
                repeat
                  BlockSize := Min(ODBCDataSize, Size - Index);
                  ODBCException(Stmt, SQLPutData(Stmt, @S[1 + Index div SizeOf(Char)], BlockSize));
                  Inc(Index, BlockSize);
                until (Index = Size);
              end;
            ftBlob:
              begin
                Size := DataSet.LibLengths^[I];
                Index := 0;
                repeat
                  BlockSize := Min(ODBCDataSize, Size - Index);
                  ODBCException(Stmt, SQLPutData(Stmt, @DataSet.LibRow^[Fields[I].FieldNo - 1][Index], BlockSize));
                  Inc(Index, BlockSize);
                until (Index = Size);
              end;
            else
              raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [Fields[I].DisplayName, Ord(Fields[I].DataType)]);
          end;
          break;
        end;
  end;
end;

{ TTExportODBC ****************************************************************}

constructor TTExportODBC.Create(const ASession: TSSession; const ADataSource, AUsername, APassword: string);
begin
  inherited Create(ASession);

  FDataSource := ADataSource;
  FUsername := AUsername;
  FPassword := APassword;
end;

procedure TTExportODBC.ExecuteFooter();
begin
  if (not SQL_SUCCEEDED(SQLEndTran(SQL_HANDLE_DBC, Handle, SQL_COMMIT))
    and (Success = daSuccess)) then
    DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False);

  inherited;
end;

procedure TTExportODBC.ExecuteHeader();
begin
  inherited;

  if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_DBC, ODBCEnv, @FHandle))) then
    DoError(ODBCError(SQL_HANDLE_ENV, ODBCEnv), nil, False)
  else if (not SQL_SUCCEEDED(SQLConnect(FHandle, PSQLTCHAR(PChar(FDataSource)), SQL_NTS, PSQLTCHAR(PChar(FUsername)), SQL_NTS, PSQLTCHAR(PChar(FPassword)), SQL_NTS))) then
    DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False)
  else if (not SQL_SUCCEEDED(SQLSetConnectAttr(Handle, SQL_ATTR_AUTOCOMMIT, SQLPOINTER(SQL_AUTOCOMMIT_OFF), 1))) then
    DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False);
end;

{ TTExportAccess **************************************************************}

constructor TTExportAccess.Create(const ASession: TSSession; const AFilename: TFileName);
begin
  inherited Create(ASession);

  Filename := AFilename;

  Access2007 := False;
end;

procedure TTExportAccess.ExecuteFooter();
begin
  if (not SQL_SUCCEEDED(SQLEndTran(SQL_HANDLE_DBC, Handle, SQL_COMMIT))
    and (Success = daSuccess)) then
    DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False);

  inherited ExecuteFooter;

  if (Success = daAbort) then
    DeleteFile(Filename);
end;

procedure TTExportAccess.ExecuteHeader();
var
  Attributes: string;
  ConnStrIn: string;
  Error: TTool.TError;
  ErrorCode: DWord;
  ErrorMsg: PChar;
  Size: Word;
begin
  if (not Access2007) then
  begin
    ConnStrIn := 'Driver={' + DriverAccess + '};DBQ=' + Filename + ';READONLY=FALSE';
    Attributes := 'CREATE_DB=' + Filename + ' General';
  end
  else
  begin
    ConnStrIn := 'Driver={' + DriverAccess2007 + '};DBQ=' + Filename + ';READONLY=FALSE';
    Attributes := 'CREATE_DBV12=' + Filename + ' General';
  end;

  while (FileExists(Filename) and not DeleteFile(Filename)) do
    DoError(SysError(), nil, True);

  if (Success = daSuccess) then
  begin
    if (not Access2007 and not SQLConfigDataSource(Application.Handle, ODBC_ADD_DSN, DriverAccess, PChar(Attributes))
      or (Access2007 and not SQLConfigDataSource(Application.Handle, ODBC_ADD_DSN, DriverAccess2007, PChar(Attributes)))) then
    begin
      Error.ErrorType := TE_ODBC;
      GetMem(ErrorMsg, SQL_MAX_MESSAGE_LENGTH * SizeOf(Char));
      SQLInstallerError(1, ErrorCode, ErrorMsg, SQL_MAX_MESSAGE_LENGTH - 1, Size);
      Error.ErrorCode := ErrorCode;
      SetString(Error.ErrorMessage, ErrorMsg, Size);
      Error.ErrorMessage := Error.ErrorMessage + '  (' + ConnStrIn + ')';
      FreeMem(ErrorMsg);
      DoError(Error, nil, False);
    end
    else if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_DBC, ODBCEnv, @Handle))) then
      DoError(ODBCError(SQL_HANDLE_ENV, ODBCEnv), nil, False)
    else if (not SQL_SUCCEEDED(SQLDriverConnect(Handle, Application.Handle, PSQLTCHAR(ConnStrIn), SQL_NTS, nil, 0, nil, SQL_DRIVER_COMPLETE))
      or not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, Handle, @Stmt))) then
      DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False)
    else if (not SQL_SUCCEEDED(SQLSetConnectAttr(Handle, SQL_ATTR_AUTOCOMMIT, SQLPOINTER(SQL_AUTOCOMMIT_OFF), 1))) then
      DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False);
  end;

  inherited;
end;

{ TTExportExcel ***************************************************************}

constructor TTExportExcel.Create(const ASession: TSSession; const AFilename: TFileName);
begin
  inherited Create(ASession);

  Filename := AFilename;

  Excel2007 := False;
  Sheet := 0;
end;

procedure TTExportExcel.ExecuteHeader();
var
  ConnStrIn: string;
begin
  while (FileExists(Filename) and not DeleteFile(Filename)) do
    DoError(SysError(), nil, True);

  if (Success = daSuccess) then
  begin
    if (not Excel2007) then
      ConnStrIn := 'Driver={' + DriverExcel + '};DBQ=' + Filename + ';READONLY=FALSE'
    else
      ConnStrIn := 'Driver={' + DriverExcel2007 + '};DBQ=' + Filename + ';READONLY=FALSE';

    if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, @ODBCEnv))
      or not SQL_SUCCEEDED(SQLSetEnvAttr(ODBCEnv, SQL_ATTR_ODBC_VERSION, SQLPOINTER(SQL_OV_ODBC3), SQL_IS_UINTEGER))) then
      DoError(ODBCError(0, SQL_NULL_HANDLE), nil, False)
    else if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_DBC, ODBCEnv, @Handle))
      or not SQL_SUCCEEDED(SQLDriverConnect(Handle, Application.Handle, PSQLTCHAR(ConnStrIn), SQL_NTS, nil, 0, nil, SQL_DRIVER_COMPLETE))) then
      DoError(ODBCError(SQL_HANDLE_ENV, ODBCEnv), nil, False)
    else if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_STMT, Handle, @Stmt))) then
      DoError(ODBCError(SQL_HANDLE_DBC, Handle), nil, False);
  end;

  inherited;
end;

procedure TTExportExcel.ExecuteFooter();
begin
  inherited;

  if (Success = daAbort) then
    DeleteFile(Filename);
end;

procedure TTExportExcel.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  Error: TTool.TError;
  I: Integer;
  SQL: string;
begin
  Inc(Sheet);
  if (not Assigned(Table)) then
    TableName := 'Sheet' + IntToStr(Sheet)
  else
    TableName := Table.Name;

  SQL := 'CREATE TABLE "' + TableName + '" (';
  for I := 0 to Length(Fields) - 1 do
  begin
    if (I > 0) then SQL := SQL + ',';

    if (Length(DestinationFields) > 0) then
      SQL := SQL + '"' + DestinationFields[I].Name + '" '
    else if (Assigned(Table)) then
      SQL := SQL + '"' + Table.Fields[I].Name + '" '
    else
      SQL := SQL + '"' + Fields[I].DisplayName + '" ';

    if (BitField(Fields[I])) then
      if (Assigned(Table) and (Table.Fields[I].Size = 1)) then
        SQL := SQL + 'BIT'
      else
        SQL := SQL + 'NUMERIC'
    else
    case (Fields[I].DataType) of
      ftString:
        SQL := SQL + 'STRING';
      ftShortInt,
      ftByte,
      ftSmallInt,
      ftWord,
      ftInteger,
      ftLongWord,
      ftLargeint,
      ftSingle,
      ftFloat,
      ftExtended:
        SQL := SQL + 'NUMERIC';
      ftDate,
      ftDateTime,
      ftTimestamp,
      ftTime:
        SQL := SQL + 'DATETIME';
      ftWideString,
      ftWideMemo,
      ftBlob:
        SQL := SQL + 'STRING';
      else
        raise EDatabaseError.CreateFMT(SUnknownFieldType + ' (%d)', [Fields[I].DisplayName, Ord(Fields[I].DataType)]);
    end;
  end;
  SQL := SQL + ')';

  while ((Success <> daAbort) and not SQL_SUCCEEDED(SQLExecDirect(Stmt, PSQLTCHAR(SQL), SQL_NTS))) do
  begin
    Error := ODBCError(SQL_HANDLE_STMT, Stmt);
    Error.ErrorMessage := Error.ErrorMessage + ' - ' + SQL;
    DoError(Error, nil, True);
  end;

  if (Success = daSuccess) then
    inherited;
end;

{ TTExportCanvas **************************************************************}

function TTExportCanvas.AllocateHeight(const Height: Integer; const DrawGridVertLines: Boolean = True): Boolean;
begin
  Result := Y + Height > ContentArea.Bottom;
  if (Result) then
  begin
    if (DrawGridVertLines and (Length(Columns) > 0)) then
      GridDrawVertLines();

    PageBreak(True);
  end;
end;

procedure TTExportCanvas.BeforeExecute();
var
  DataHandle: TMySQLConnection.TDataResult;
  DataSet: TMySQLQuery;
  I: Integer;
  J: Integer;
  K: Integer;
  SQL: string;
  Table: TSTable;
  Tables: TList;
begin
  inherited;

  if (Success = daSuccess) then
  begin
    SetLength(MaxFieldsCharLengths, 0);

    Tables := TList.Create();

    SQL := '';
    for I := 0 to Items.Count - 1 do
      if ((Items[I] is TDBObjectItem) and (TDBObjectItem(Items[I]).DBObject is TSTable)) then
      begin
        Table := TSTable(TDBObjectItem(Items[I]).DBObject);
        Tables.Add(Table);

        SQL := SQL + 'SELECT ';
        for J := 0 to Table.Fields.Count - 1 do
        begin
          if (J > 0) then SQL := SQL + ',';
          if (Table.Fields[J].FieldType in LOBFieldTypes) then
            SQL := SQL + '0'
          else if (Table.Fields[J].FieldType = mfBit) then
            SQL := SQL + 'CHAR_LENGTH(CONV(MAX(' + Session.EscapeIdentifier(Table.Fields[J].Name) + ')+0,8,2))'
          else
            SQL := SQL + 'MAX(CHAR_LENGTH(' + Session.EscapeIdentifier(Table.Fields[J].Name) + '))';
          SQL := SQL + ' AS ' + Session.EscapeIdentifier(Table.Fields[J].Name);
        end;
        SQL := SQL + ' FROM ' + Session.EscapeIdentifier(Table.Database.Name) + '.' + Session.EscapeIdentifier(Table.Name) + ';' + #13#10;
      end;

    if ((Success = daSuccess) and (Tables.Count > 0)) then
    begin
      for J := 0 to Tables.Count - 1 do
        if (Success = daSuccess) then
        begin
          if (J = 0) then
            while ((Success <> daAbort) and not Session.FirstResult(DataHandle, SQL)) do
              DoError(DatabaseError(Session), nil, True, SQL)
          else
            if ((Success = daSuccess) and not Session.NextResult(DataHandle)) then
              DoError(DatabaseError(Session), nil, False);
          if (Success = daSuccess) then
            for I := 0 to Items.Count - 1 do
              if ((Items[I] is TDBObjectItem) and (TDBObjectItem(Items[I]).DBObject = Tables[J])) then
              begin
                SetLength(MaxFieldsCharLengths, Length(MaxFieldsCharLengths) + 1);
                SetLength(MaxFieldsCharLengths[Length(MaxFieldsCharLengths) - 1], TSTable(Tables[J]).Fields.Count);
                DataSet := TMySQLQuery.Create(nil);
                DataSet.Open(DataHandle);
                if (not DataSet.IsEmpty) then
                  for K := 0 to DataSet.FieldCount - 1 do
                    MaxFieldsCharLengths[Length(MaxFieldsCharLengths) - 1][K] := DataSet.Fields[K].AsInteger;
                DataSet.Free();
              end;
        end;
      Session.CloseResult(DataHandle);
    end;

    Tables.Free();
  end;
end;

procedure TTExportCanvas.ContentTextOut(const Text: string; const ExtraPadding: Integer = 0);
var
  I: Integer;
  R: TRect;
  S: string;
  StringList: TStringList;
begin
  StringList := TStringList.Create();
  StringList.Text := Text;

  for I := 0 to StringList.Count - 1 do
  begin
    S := ReplaceStr(StringList[I], '&', '&&');

    R := Rect(ContentArea.Left, Y, ContentArea.Right, ContentArea.Bottom);
    Canvas.TextRect(R, S, [tfCalcRect, tfWordBreak]);

    AllocateHeight(ExtraPadding + R.Bottom - R.Top + Padding + ExtraPadding);

    if (Y > ContentArea.Top) then
      Inc(Y, ExtraPadding);
    R := Rect(ContentArea.Left, Y, ContentArea.Right, Y + R.Bottom - R.Top);
    Canvas.TextRect(R, S, [tfWordBreak]);

    Inc(Y, R.Bottom - R.Top + Padding + ExtraPadding);
  end;

  StringList.Free();
end;

constructor TTExportCanvas.Create(const ASession: TSSession);
var
  NonClientMetrics: TNonClientMetrics;
begin
  inherited Create(ASession);

  DateTime := Session.ServerDateTime;
  ContentFont := TFont.Create();
  GridFont := TFont.Create();
  IndexBackground := False;
  NULLText := True;
  PageFont := TFont.Create();
  PageNumber.Row := 1;
  SQLFont := TFont.Create();

  NonClientMetrics.cbSize := SizeOf(NonClientMetrics);
  if (SystemParametersInfo(SPI_GETNONCLIENTMETRICS, SizeOf(NonClientMetrics), @NonClientMetrics, 0)) then
    ContentFont.Handle := CreateFontIndirect(NonClientMetrics.lfMessageFont)
  else
    ContentFont.Assign(Canvas.Font);
  ContentFont.Color := clBlack;

  GridFont.Name := Preferences.GridFontName;
  GridFont.Style := Preferences.GridFontStyle;
  GridFont.Charset := Preferences.GridFontCharset;
  GridFont.Color := clBlack;
  GridFont.Size := Preferences.GridFontSize;

  SQLFont.Name := Preferences.SQLFontName;
  SQLFont.Style := Preferences.SQLFontStyle;
  SQLFont.Charset := Preferences.SQLFontCharset;
  SQLFont.Color := clBlack;
  SQLFont.Size := Preferences.SQLFontSize;

  PageFont.Assign(ContentFont);
  PageFont.Size := PageFont.Size - 2;

  ContentArea.Left := Margins.Left;
  ContentArea.Top := Margins.Top;
  ContentArea.Right := PageWidth - Margins.Right;
  ContentArea.Bottom := PageHeight - (Margins.Bottom + -PageFont.Height + Padding + LineHeight + 10);

  Y := ContentArea.Top;

  SetFont(ContentFont);
end;

destructor TTExportCanvas.Destroy();
begin
  ContentFont.Free();
  GridFont.Free();
  PageFont.Free();
  SQLFont.Free();

  inherited;
end;

procedure TTExportCanvas.ExecuteDatabaseHeader(const Database: TSDatabase);
begin
  if (Assigned(Database)) then
  begin
    SetFont(ContentFont, ContentFont.Size + 6, ContentFont.Style + [fsBold]);

    ContentTextOut(ReplaceStr(Preferences.LoadStr(38), '&', '') + ': ' + Database.Name, 3 * Padding);
  end;
end;

procedure TTExportCanvas.ExecuteEvent(const Event: TSEvent);
begin
  SetFont(ContentFont, ContentFont.Size + 4, ContentFont.Style + [fsBold]);

  ContentTextOut(Preferences.LoadStr(812) + ': ' + Event.Name, 2 * Padding);


  SetFont(SQLFont);
  ContentTextOut(Event.Source);
end;

procedure TTExportCanvas.ExecuteFooter();
begin
  PageFooter();

  inherited;
end;

procedure TTExportCanvas.ExecuteRoutine(const Routine: TSRoutine);
begin
  SetFont(ContentFont, ContentFont.Size + 4, ContentFont.Style + [fsBold]);

  if (Routine is TSProcedure) then
    ContentTextOut(Preferences.LoadStr(768) + ': ' + Routine.Name, 2 * Padding)
  else
    ContentTextOut(Preferences.LoadStr(769) + ': ' + Routine.Name, 2 * Padding);


  SetFont(SQLFont);
  ContentTextOut(Routine.Source);
end;

procedure TTExportCanvas.ExecuteTableFooter(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
begin
  if (Length(Columns) > 0) then
  begin
    GridDrawVertLines();
    SetLength(Columns, 0);
  end;

  Inc(Y, -Canvas.Font.Height);
end;

procedure TTExportCanvas.ExecuteTableHeader(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);
var
  I: Integer;
  J: Integer;
  K: Integer;
  GridData: TGridData;
  MaxTextWidth: Integer;
  S: string;
  S2: string;
  StringList: TStringList;
begin
  SetFont(ContentFont, ContentFont.Size + 4, ContentFont.Style + [fsBold]);

  if (not (DataSet is TMySQLDataSet)) then
    if (Table is TSBaseTable) then
    begin
      ContentTextOut(ReplaceStr(Preferences.LoadStr(302), '&', '') + ': ' + Table.Name, 2 * Padding);
      if (TSBaseTable(Table).Comment <> '') then
        ContentTextOut(ReplaceStr(Preferences.LoadStr(111), '&', '') + ': ' + TSBaseTable(Table).Comment, 2 * Padding);
    end
    else if (Table is TSView) then
      ContentTextOut(ReplaceStr(Preferences.LoadStr(738), '&', '') + ': ' + Table.Name, 2 * Padding)
    else if (Structure) then
      ContentTextOut(ReplaceStr(Preferences.LoadStr(216), '&', ''), 2 * Padding);

  if (Structure) then
    if (DataSet is TMySQLDataSet) then
    begin
      SetFont(ContentFont, ContentFont.Size + 2, ContentFont.Style + [fsBold]);
      ContentTextOut(ReplaceStr(Preferences.LoadStr(794), '&', '') + ':', Padding);

      SetFont(SQLFont);
      StringList := TStringList.Create();
      StringList.Text := DataSet.CommandText + ';';
      for I := 0 to StringList.Count - 1 do
        ContentTextOut(StringList[I]);
      StringList.Free();
    end
    else
    begin
      if ((Table is TSBaseTable) and (TSBaseTable(Table).Keys.Count > 0)) then
      begin
        SetFont(ContentFont, ContentFont.Size + 2, ContentFont.Style + [fsBold]);
        ContentTextOut(Preferences.LoadStr(458) + ':', Padding);

        if (Session.ServerVersion < 50503) then
          SetLength(Columns, 3)
        else
          SetLength(Columns, 4);
        Columns[0].HeaderText := ReplaceStr(Preferences.LoadStr(35), '&', '');
        Columns[1].HeaderText := Preferences.LoadStr(69);
        Columns[2].HeaderText := ReplaceStr(Preferences.LoadStr(73), '&', '');
        if (Session.ServerVersion >= 50503) then
          Columns[3].HeaderText := ReplaceStr(Preferences.LoadStr(111), '&', '');

        SetLength(GridData, TSBaseTable(Table).Keys.Count);
        for I := 0 to TSBaseTable(Table).Keys.Count - 1 do
        begin
          SetLength(GridData[I], Length(Columns));

          for J := 0 to Length(Columns) - 1 do
          begin
            GridData[I][J].Bold := False;
            GridData[I][J].Gray := False;
          end;

          GridData[I][0].Bold := TSBaseTable(Table).Keys[I].Primary;
          GridData[I][0].Text := TSBaseTable(Table).Keys[I].Caption;
          S := '';
          for K := 0 to TSBaseTable(Table).Keys[I].Columns.Count - 1 do
            begin
              if (S <> '') then S := S + ', ';
              S := S + TSBaseTable(Table).Keys[I].Columns[K].Field.Name;
            end;
          GridData[I][1].Text := S;
          if (TSBaseTable(Table).Keys[I].Unique) then
            GridData[I][2].Text := 'unique'
          else if (TSBaseTable(Table).Keys[I].Fulltext) then
            GridData[I][2].Text := 'fulltext'
          else
            GridData[I][2].Text := '';
          if (Session.ServerVersion >= 50503) then
            GridData[I][3].Text := TSBaseTable(Table).Keys[I].Comment;
        end;

        GridOut(GridData);
      end;

      {------------------------------------------------------------------------}

      SetFont(ContentFont, ContentFont.Size + 2, ContentFont.Style + [fsBold]);
      ContentTextOut(Preferences.LoadStr(253) + ':', Padding);

      if (Session.ServerVersion < 40100) then
        SetLength(Columns, 5)
      else
        SetLength(Columns, 6);
      Columns[0].HeaderText := ReplaceStr(Preferences.LoadStr(35), '&', '');
      Columns[1].HeaderText := Preferences.LoadStr(69);
      Columns[2].HeaderText := Preferences.LoadStr(71);
      Columns[3].HeaderText := Preferences.LoadStr(72);
      Columns[4].HeaderText := ReplaceStr(Preferences.LoadStr(73), '&', '');
      if (Session.ServerVersion >= 40100) then
        Columns[5].HeaderText := ReplaceStr(Preferences.LoadStr(111), '&', '');


      SetLength(GridData, Table.Fields.Count);
      for I := 0 to Table.Fields.Count - 1 do
      begin
        SetLength(GridData[I], Length(Columns));

        for J := 0 to Length(Columns) - 1 do
        begin
          GridData[I][J].Bold := False;
          GridData[I][J].Gray := False;
        end;

        GridData[I][0].Bold := Table.Fields[I].InPrimaryKey;
        GridData[I][0].Text := Table.Fields[I].Name;
        GridData[I][1].Text := Table.Fields[I].DBTypeStr();
        if (Table.Fields[I].NullAllowed) then
          GridData[I][2].Text := Preferences.LoadStr(74)
        else
          GridData[I][2].Text := Preferences.LoadStr(75);
        if (Table.Fields[I].AutoIncrement) then
          GridData[I][3].Text := '<auto_increment>'
        else if (Table.Fields[I].Default = 'NULL') then
        begin
          GridData[I][3].Gray := True;
          GridData[I][3].Text := '<' + Preferences.LoadStr(71) + '>';
        end
        else if (Table.Fields[I].Default = 'CURRENT_TIMESTAMP') then
          GridData[I][3].Text := '<INSERT-TimeStamp>'
        else if (Table.Fields[I].Default <> '') then
          GridData[I][3].Text := Table.Fields[I].UnescapeValue(Table.Fields[I].Default)
        else
          GridData[I][3].Text := '';
        S := '';
        if ((Table is TSBaseTable) and (Table.Fields[I].FieldType in TextFieldTypes)) then
        begin
          if ((Table.Fields[I].Charset <> '') and (Table.Fields[I].Charset <> TSBaseTable(Table).DefaultCharset)) then
            S := S + Table.Fields[I].Charset;
          if ((Table.Fields[I].Collation <> '') and (Table.Fields[I].Collation <> TSBaseTable(Table).Collation)) then
          begin
            if (S <> '') then S := S + ', ';
            S := S + Table.Fields[I].Collation;
          end;
        end;
        GridData[I][4].Text := S;
        if (Session.ServerVersion >= 40100) then
          GridData[I][5].Text := TSBaseTableField(Table.Fields[I]).Comment;
      end;

      GridOut(GridData);

      {------------------------------------------------------------------------}

      if ((Table is TSBaseTable) and (TSBaseTable(Table).ForeignKeys.Count > 0)) then
      begin
        SetFont(ContentFont, ContentFont.Size + 2, ContentFont.Style + [fsBold]);
        ContentTextOut(Preferences.LoadStr(459) + ':', Padding);


        SetLength(Columns, 3);
        Columns[0].HeaderText := ReplaceStr(Preferences.LoadStr(35), '&', '');
        Columns[1].HeaderText := Preferences.LoadStr(69);
        Columns[2].HeaderText := Preferences.LoadStr(73);

        SetLength(GridData, TSBaseTable(Table).ForeignKeys.Count);
        for I := 0 to TSBaseTable(Table).ForeignKeys.Count - 1 do
        begin
          SetLength(GridData[I], Length(Columns));

          for J := 0 to Length(Columns) - 1 do
          begin
            GridData[I][J].Bold := False;
            GridData[I][J].Gray := False;
          end;

          GridData[I][0].Text := TSBaseTable(Table).ForeignKeys[I].Name;
          GridData[I][1].Text := TSBaseTable(Table).ForeignKeys[I].DBTypeStr();
          S := '';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtCascade) then S := 'cascade on delete';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtSetNull) then S := 'set NULL on delete';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtSetDefault) then S := 'set default on delete';
          if (TSBaseTable(Table).ForeignKeys[I].OnDelete = dtNoAction) then S := 'no action on delete';
          S2 := '';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utCascade) then S2 := 'cascade on update';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utSetNull) then S2 := 'set NULL on update';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utSetDefault) then S2 := 'set default on update';
          if (TSBaseTable(Table).ForeignKeys[I].OnUpdate = utNoAction) then S2 := 'no action on update';
          if (S <> '') and (S2 <> '') then S := S + ', ';
          S := S + S2;
          GridData[I][2].Text := S;
        end;

        GridOut(GridData);
      end;
    end;

  if (Data) then
  begin
    if (Structure) then
    begin
      SetFont(ContentFont, ContentFont.Size + 2, ContentFont.Style + [fsBold]);

      ContentTextOut(Preferences.LoadStr(580) + ':', Padding);
    end;

    SetFont(GridFont);

    if (DataSet is TMySQLDataSet) then
    begin
      SetLength(Columns, Length(Fields));

      for J := 0 to Length(Fields) - 1 do
      begin
        Columns[J].HeaderBold := Fields[J].IsIndexField;
        if (J < Length(DestinationFields)) then
          Columns[J].HeaderText := DestinationFields[J].Name
        else
          Columns[J].HeaderText := Fields[J].DisplayName;


        if (Columns[J].HeaderBold) then Canvas.Font.Style := Canvas.Font.Style + [fsBold];

        if (GeometryField(Fields[J])) then
          Columns[J].Width := Canvas.TextWidth('<GEO>')
        else if (Fields[J].DataType = ftWideMemo) then
          Columns[J].Width := Canvas.TextWidth('<MEMO>')
        else if (Fields[J].DataType = ftBytes) then
          Columns[J].Width := Canvas.TextWidth('<BINARY>')
        else if (Fields[J].DataType = ftBlob) then
          Columns[J].Width := Canvas.TextWidth('<BLOB>')
        else
          Columns[J].Width := TMySQLDataSet(DataSet).GetMaxTextWidth(Fields[J], Canvas.TextWidth);
        Columns[J].Width := Max(Columns[J].Width, Canvas.TextWidth(Columns[J].HeaderText));
        if (NullText and not Fields[J].Required) then
          Columns[J].Width := Max(Columns[J].Width, Canvas.TextWidth('<NULL>'));
        Columns[J].Width := Min(Columns[J].Width, ContentArea.Right - ContentArea.Left - 2 * Padding - 2 * LineWidth);

        if (Columns[J].HeaderBold) then Canvas.Font.Style := Canvas.Font.Style - [fsBold];
      end;
    end
    else
    begin
      for I := 0 to Items.Count - 1 do
        if ((Items[I] is TDBObjectItem) and (TDBObjectItem(Items[I]).DBObject = Table)) then
        begin
          SetLength(Columns, Length(Fields));

          for J := 0 to Length(Fields) - 1 do
          begin
            Columns[J].HeaderBold := Fields[J].IsIndexField;
            if (J < Length(DestinationFields)) then
              Columns[J].HeaderText := DestinationFields[J].Name
            else
              Columns[J].HeaderText := Fields[J].DisplayName;


            if (Columns[J].HeaderBold) then Canvas.Font.Style := Canvas.Font.Style + [fsBold];

            Columns[J].Width := Canvas.TextWidth(StringOfChar('e', MaxFieldsCharLengths[I][J]));
            Columns[J].Width := Max(Columns[J].Width, Canvas.TextWidth(Columns[J].HeaderText));
            if (NullText and not Fields[J].Required) then
              Columns[J].Width := Max(Columns[J].Width, Canvas.TextWidth('<NULL>'));
            Columns[J].Width := Min(Columns[J].Width, ContentArea.Right - ContentArea.Left - 2 * Padding - 2 * LineWidth);

            if (Columns[J].HeaderBold) then Canvas.Font.Style := Canvas.Font.Style - [fsBold];
          end;
        end;
    end;

    GridHeader();
  end;
end;

procedure TTExportCanvas.ExecuteTableRecord(const Table: TSTable; const Fields: array of TField; const DataSet: TMySQLQuery);

  function FieldText(const Field: TField): string;
  begin
    if (GeometryField(Field)) then
      Result := '<GEO>'
    else if (Field.DataType = ftWideMemo) then
      Result := '<MEMO>'
    else if (Field.DataType = ftBytes) then
      Result := '<BINARY>'
    else if (Field.DataType = ftBlob) then
      Result := '<BLOB>'
    else if (Field.IsNull and NULLText) then
      Result := '<NULL>'
    else
      Result := DataSet.GetAsString(Field);
  end;

var
  HeaderHeight: Integer;
  I: Integer;
  MaxRowHeight: Integer;
  Text: string;
  TextFormat: TTextFormat;
begin
  MaxRowHeight := 0;
  for I := 0 to Length(Fields) - 1 do
  begin
    Text := FieldText(Fields[I]);
    if (Fields[I].DataType in RightAlignedDataTypes) then
      TextFormat := [tfRight]
    else if (Fields[I].DataType in NotQuotedDataTypes) then
      TextFormat := []
    else
      TextFormat := [tfWordBreak];
    MaxRowHeight := Max(MaxRowHeight, GridTextOut(Columns[I], Text, [tfCalcRect] + TextFormat, Fields[I].IsIndexField, Fields[I].IsNull));
  end;

  if (AllocateHeight(MaxRowHeight + LineHeight)) then
  begin
    HeaderHeight := Y;
    GridHeader();
    HeaderHeight := Y - HeaderHeight;
    for I := 0 to Length(Columns) - 1 do
      Columns[I].Rect.Offset(0, HeaderHeight);
  end;

  for I := 0 to Length(Fields) - 1 do
  begin
    Text := FieldText(Fields[I]);
    if (Fields[I].DataType in RightAlignedDataTypes) then
      TextFormat := [tfRight]
    else if (Fields[I].DataType in NotQuotedDataTypes) then
      TextFormat := []
    else
      TextFormat := [tfWordBreak];
    GridTextOut(Columns[I], Text, TextFormat, Fields[I].IsIndexField, Fields[I].IsNull);
  end;

  Inc(Y, MaxRowHeight);
  GridDrawHorzLine(Y);
end;

procedure TTExportCanvas.ExecuteTrigger(const Trigger: TSTrigger);
begin
  SetFont(ContentFont, ContentFont.Size + 2, ContentFont.Style + [fsBold]);

  ContentTextOut(Preferences.LoadStr(788) + ': ' + Trigger.Name, 2 * Padding);


  SetFont(SQLFont);
  ContentTextOut(Trigger.Source);
end;

procedure TTExportCanvas.GridDrawHorzLine(const Y: Integer);
var
  I: Integer;
  X: Integer;
begin
  Canvas.Pen.Width := LineHeight;

  X := Columns[0].Left - LineWidth;
  Canvas := Columns[0].Canvas;
  for I := 0 to Length(Columns) do
  begin
    if ((I = Length(Columns)) or (Columns[I].Left < X)) then
    begin
      Canvas.MoveTo(ContentArea.Left, Y);
      Canvas.LineTo(X + LineWidth, Canvas.PenPos.Y);

      if (I < Length(Columns)) then
        X := Columns[I].Left - LineWidth;
    end;

    if (I < Length(Columns)) then
    begin
      Inc(X, Padding + Columns[I].Width + Padding + LineWidth);
      Canvas := Columns[I].Canvas;
    end;
  end;
end;

procedure TTExportCanvas.GridDrawVertLines();
var
  I: Integer;
begin
  Canvas.Pen.Width := LineWidth;
  for I := 0 to Length(Columns) - 1 do
  begin
    if ((I = 0) or (Columns[I].Canvas <> Canvas)) then
    begin
      Canvas := Columns[I].Canvas;

      // Left vertical line
      Canvas.MoveTo(ContentArea.Left, GridTop);
      Canvas.LineTo(Canvas.PenPos.X, Y);
    end;

    // Right column vertical line
    Canvas.MoveTo(Columns[I].Left + Padding + Columns[I].Width + Padding + LineHeight, GridTop);
    Canvas.LineTo(Canvas.PenPos.X, Y);
  end;
end;

procedure TTExportCanvas.GridHeader();
var
  I: Integer;
  RowHeight: Integer;
  Text: string;
  X: Integer;
begin
  GridTop := Y; RowHeight := 0;

  SetFont(GridFont);
  X := ContentArea.Left + LineWidth; Y := GridTop;

  for I := 0 to Length(Columns) - 1 do
  begin
    if (X + Columns[I].Width > ContentArea.Right) then
    begin
      PageBreak(False);

      SetFont(GridFont);
      X := ContentArea.Left + LineWidth; Y := GridTop;
    end;

    Columns[I].Canvas := Canvas;
    Columns[I].Left := X;

    Text := Columns[I].HeaderText;
    RowHeight := Max(RowHeight, GridTextOut(Columns[I], Columns[I].HeaderText, [tfCalcRect], Columns[I].HeaderBold, False));

    Inc(X, Padding + Columns[I].Width + Padding + LineWidth);
  end;

  for I := 0 to Length(Columns) - 1 do
  begin
    GridTextOut(Columns[I], Columns[I].HeaderText, [], Columns[I].HeaderBold, False);
    Columns[I].Canvas.Font.Assign(GridFont);
  end;

  GridDrawHorzLine(GridTop);
  Inc(Y, RowHeight);
  GridDrawHorzLine(Y);
end;

procedure TTExportCanvas.GridOut(var GridData: TGridData);
var
  I: Integer;
  J: Integer;
  MaxRowHeight: Integer;
  Text: string;
begin
  SetFont(GridFont);

  MaxRowHeight := 0;
  SetLength(Columns, Length(GridData[0]));
  for J := 0 to Length(Columns) - 1 do
  begin
    Columns[J].Width := Canvas.TextWidth(Columns[J].HeaderText);
    for I := 0 to Length(GridData) - 1 do
    begin
      if (GridData[I][J].Bold) then Canvas.Font.Style := Canvas.Font.Style + [fsBold];
      MaxRowHeight := Max(MaxRowHeight, Canvas.TextHeight(GridData[I][J].Text));
      Columns[J].Width := Max(Columns[J].Width, Canvas.TextWidth(GridData[I][J].Text));
      if (GridData[I][J].Bold) then Canvas.Font.Style := Canvas.Font.Style - [fsBold];
    end;
    Columns[J].Width := Min(Columns[J].Width, ContentArea.Right - ContentArea.Left - 2 * Padding - 2 * LineWidth);

    Columns[J].Canvas := Canvas;
  end;

  AllocateHeight(LineHeight + MaxRowHeight + LineHeight, False);
  GridHeader();

  for I := 0 to Length(GridData) - 1 do
  begin
    MaxRowHeight := 0;
    for J := 0 to Length(GridData[I]) - 1 do
    begin
      if (GridData[I][J].Bold) then Canvas.Font.Style := Canvas.Font.Style + [fsBold];
      Text := GridData[I][J].Text;
      MaxRowHeight := Max(MaxRowHeight, GridTextOut(Columns[J], Text, [tfCalcRect], False, False));
      if (GridData[I][J].Bold) then Canvas.Font.Style := Canvas.Font.Style - [fsBold];
    end;

  if (AllocateHeight(LineHeight + MaxRowHeight + LineHeight)) then
      GridHeader();

    for J := 0 to Length(GridData[I]) - 1 do
    begin
      if (GridData[I][J].Bold) then Canvas.Font.Style := Canvas.Font.Style + [fsBold];
      if (GridData[I][J].Gray) then Canvas.Font.Color := clGray;
      Text := GridData[I][J].Text;
      GridTextOut(Columns[J], Text, [], False, False);
      if (GridData[I][J].Gray) then Canvas.Font.Color := clBlack;
      if (GridData[I][J].Bold) then Canvas.Font.Style := Canvas.Font.Style - [fsBold];
    end;

    Inc(Y, MaxRowHeight);
    GridDrawHorzLine(Y);
  end;

  GridDrawVertLines();

  Inc(Y, -Canvas.Font.Height);

  for J := 0 to Length(GridData) - 1 do
    SetLength(GridData[J], 0);
  SetLength(GridData, 0);
  SetLength(Columns, 0);
end;

function TTExportCanvas.GridTextOut(var Column: TColumn; const Text: string; const TextFormat: TTextFormat; const Bold, Gray: Boolean): Integer;
var
  R: TRect;
begin
  if (Bold) then Column.Canvas.Font.Style := Column.Canvas.Font.Style + [fsBold];

  R := Rect(Column.Left + Padding, Y + Padding - 1, Column.Left + Padding + Column.Width + Padding - 1, Y + Padding + -Canvas.Font.Height + Padding);
  if (tfCalcRect in TextFormat) then
  begin
    Column.Rect := R;
    Windows.DrawText(Column.Canvas.Handle, PChar(Text), Length(Text), R, TTextFormatFlags([tfCalcRect] + TextFormat));
    Column.Rect.Bottom := R.Bottom;
  end
  else if (Text <> '') then
  begin
    if (Gray) then Column.Canvas.Font.Color := clGray;

    if ((Column.Rect.Right < R.Right) or (Column.Rect.Bottom < R.Bottom) or (tfRight in TextFormat)) then
      Windows.DrawText(Column.Canvas.Handle, PChar(Text), Length(Text), Column.Rect, TTextFormatFlags(TextFormat))
    else
      Windows.ExtTextOut(Column.Canvas.Handle, R.Left, R.Top, ETO_CLIPPED, R, Text, Length(Text), nil);

    if (Gray) then Column.Canvas.Font.Color := clBlack;
  end;

  if (Self is TTExportPDF) then
    Result := Column.Rect.Bottom - Y
  else
    Result := Column.Rect.Bottom - Y + Padding;

  if (Bold) then Column.Canvas.Font.Style := Column.Canvas.Font.Style - [fsBold];
end;

procedure TTExportCanvas.PageBreak(const NewPageRow: Boolean);
var
  Font: TFont;
begin
  if (not Assigned(Canvas)) then
    Font := nil
  else
  begin
    Font := TFont.Create();
    Font.Assign(Canvas.Font);
    PageFooter();
  end;

  if (not NewPageRow) then
    Inc(PageNumber.Column)
  else
  begin
    Inc(PageNumber.Row);
    PageNumber.Column := 0;
  end;

  AddPage(NewPageRow);

  if (Assigned(Font)) then
  begin
    SetFont(Font);
    Font.Free();
  end;

  Y := ContentArea.Top;
end;

procedure TTExportCanvas.PageFooter();
var
  R: TRect;
  Text: string;
begin
  Y := ContentArea.Bottom + 5 * Padding;

  Canvas.Pen.Width := LineHeight;
  // Horizontal line
  Canvas.MoveTo(ContentArea.Left, Y);
  Canvas.LineTo(ContentArea.Right, Canvas.PenPos.Y);

  Inc (Y, LineHeight + Padding);


  SetFont(PageFont);

  R := Rect(ContentArea.Left, Y, ContentArea.Right, PageHeight);
  Text := SysUtils.DateTimeToStr(DateTime, LocaleFormatSettings);
  Canvas.TextRect(R, Text, []);

  R := Rect(ContentArea.Left, Y, ContentArea.Right, PageHeight);
  Text := Session.Account.Connection.Host;
  if (Session.Account.Connection.Port <> MYSQL_PORT) then
    Text := Text + ':' + IntToStr(Session.Account.Connection.Port);
  Text := Text + '  (MySQL: ' + ReplaceStr(Session.ServerVersionStr, '&', '&&') + ')';
  Canvas.TextRect(R, Text, [tfCenter]);

  R := Rect(ContentArea.Left, Y, ContentArea.Right, PageHeight);
  Text := IntToStr(PageNumber.Row);
  if (PageNumber.Column > 0) then
    Text := Text + Chr(Ord('a') - 1 + PageNumber.Column);
  Canvas.TextRect(R, Text, [tfRight]);
end;

procedure TTExportCanvas.SetFont(const Font: TFont; const Size: Integer = -1; const Style: TFontStyles = []);
begin
  Canvas.Font.Assign(Font);
  if (Size > 0) then
  begin
    if (Size <> Font.Size) then
      Canvas.Font.Size := Size;
    if (Style <> Font.Style) then
      Canvas.Font.Style := Style;
  end;
end;

{ TTExportPrint ***************************************************************}

procedure TTExportPrint.AddPage(const NewPageRow: Boolean);
var
  FontSize: Integer;
  I: Integer;
begin
  if (NewPageRow) then
  begin
    for I := 0 to Length(Pages) - 1 do
    begin
      if (Success = daSuccess) then
        PrintPage(Pages[I]);
      Pages[I].Free();
    end;
    SetLength(Pages, 0);
  end;

  if (Success <> daSuccess) then
    Canvas := nil
  else
  begin
    SetLength(Pages, Length(Pages) + 1);
    Pages[Length(Pages) - 1] := TBitmap.Create();
    Pages[Length(Pages) - 1].Canvas.Handle := CreateCompatibleDC(Handle);
    Pages[Length(Pages) - 1].Monochrome := True;
    Pages[Length(Pages) - 1].SetSize(PageWidth, PageHeight);
    Canvas := Pages[Length(Pages) - 1].Canvas;

    if (Canvas.Font.PixelsPerInch <> GetDeviceCaps(Handle, LOGPIXELSY)) then
    begin
      FontSize := Canvas.Font.Size;
      Canvas.Font.PixelsPerInch := GetDeviceCaps(Handle, LOGPIXELSY);
      Canvas.Font.Size := FontSize;
    end;
  end;
end;

procedure TTExportPrint.AfterExecute();
var
  I: Integer;
begin
  for I := 0 to Length(Pages) - 1 do
  begin
    if (Success = daSuccess) then
      PrintPage(Pages[I]);
    Pages[I].Free();
  end;
  SetLength(Pages, 0);

  if (EndDoc(Handle) <= 0) then
    RaiseLastOSError();

  inherited;
end;

procedure TTExportPrint.BeforeExecute();
var
  DocInfo: TDocInfo;
begin
  inherited;

  if (Success = daSuccess) then
  begin
    ZeroMemory(@DocInfo, SizeOf(DocInfo));
    DocInfo.cbSize := SizeOf(DocInfo);
    DocInfo.lpszDocName := PChar(FTitle);
    if (StartDoc(Handle, DocInfo) <= 0) then
      RaiseLastOSError();
  end;
end;

constructor TTExportPrint.Create(const ASession: TSSession; const APrinterName: string; const ATitle: string);
var
  Size: Integer;
  XResolution: Integer;
begin
  FTitle := ATitle;

  if (not OpenPrinter(PChar(APrinterName), Printer, nil)) then
    RaiseLastOSError();

  Size := DocumentProperties(Application.Handle, Printer, nil, nil, nil, 0);

  GetMem(DevMode, Size);
  if (DocumentProperties(Application.Handle, Printer, nil, DevMode, nil, DM_OUT_BUFFER) <> IDOK) then
    RaiseLastOSError();

  Handle := CreateDC(nil, PChar(APrinterName), nil, DevMode);

  PageWidth := GetDeviceCaps(Handle, HorzRes);
  PageHeight := GetDeviceCaps(Handle, VertRes);

  if (DevMode^.dmPrintQuality > 0) then
    XResolution := DevMode^.dmPrintQuality
  else
    XResolution := DevMode^.dmYResolution;

  Margins.Left := Round(XResolution * MarginsMilliInch.Left / 1000);
  Margins.Top := Round(DevMode^.dmYResolution * MarginsMilliInch.Top / 1000);
  Margins.Right := Round(XResolution * MarginsMilliInch.Right / 1000);
  Margins.Bottom := Round(DevMode^.dmYResolution * MarginsMilliInch.Bottom / 1000);

  Padding := Round(DevMode^.dmYResolution * PaddingMilliInch / 1000);

  LineWidth := Round(XResolution * LineWidthMilliInch / 1000);
  LineHeight := Round(DevMode^.dmYResolution * LineHeightMilliInch / 1000);

  SetLength(Pages, 0);
  Success := daSuccess;
  AddPage(False);

  inherited Create(ASession);
end;

destructor TTExportPrint.Destroy();
begin
  DeleteDC(Handle);
  FreeMem(DevMode);
  ClosePrinter(Printer);

  inherited;
end;

procedure TTExportPrint.PrintPage(const Page: TBitmap);
begin
  if (StartPage(Handle) <= 0) then
    RaiseLastOSError();
  if (not BitBlt(Handle, 0, 0, PageWidth, PageHeight, Page.Canvas.Handle, 0, 0, SRCCOPY)) then
    RaiseLastOSError();
  if (EndPage(Handle) <= 0) then
    RaiseLastOSError();
end;

{ TTExportPDF *****************************************************************}

procedure TTExportPDF.AddPage(const NewPageRow: Boolean);
begin
  PDF.AddPage();

  Canvas := PDF.VCLCanvas;
end;

constructor TTExportPDF.Create(const ASession: TSSession; const AFilename: TFileName);
begin
  PDF := TPDFDocumentGDI.Create(False, CP_UTF8, False);
  PDF.DefaultPaperSize := CurrentPrinterPaperSize();
  PDF.Info.Data.AddItemTextString('Producer', SysUtils.LoadStr(1000));
  AddPage(True);

  PageWidth := Trunc(Integer(PDF.DefaultPageWidth) * GetDeviceCaps(Canvas.Handle, LOGPIXELSX) / 72); // PDF expect 72 pixels per inch
  PageHeight := Trunc(Integer(PDF.DefaultPageHeight) * GetDeviceCaps(Canvas.Handle, LOGPIXELSY) / 72); // PDF expect 72 pixels per inch

  Margins.Left := Round(GetDeviceCaps(Canvas.Handle, LOGPIXELSX) * MarginsMilliInch.Left / 1000);
  Margins.Top := Round(GetDeviceCaps(Canvas.Handle, LOGPIXELSY) * MarginsMilliInch.Top / 1000);
  Margins.Right := Round(GetDeviceCaps(Canvas.Handle, LOGPIXELSX) * MarginsMilliInch.Right / 1000);
  Margins.Bottom := Round(GetDeviceCaps(Canvas.Handle, LOGPIXELSY) * MarginsMilliInch.Bottom / 1000);

  Padding := Round(GetDeviceCaps(Canvas.Handle, LOGPIXELSY) * PaddingMilliInch / 1000);

  LineWidth := Round(GetDeviceCaps(Canvas.Handle, LOGPIXELSX) * LineWidthMilliInch / 1000);
  LineHeight := Round(GetDeviceCaps(Canvas.Handle, LOGPIXELSY) * LineHeightMilliInch / 1000);

  inherited Create(ASession);

  Filename := AFilename;
end;

destructor TTExportPDF.Destroy();
begin
  inherited;

  PDF.Free();
end;

procedure TTExportPDF.ExecuteFooter();
begin
  inherited;

  while ((Success <> daAbort) and not PDF.SaveToFile(Filename)) do
    DoError(SysError(), nil, True);
end;

procedure TTExportPDF.ExecuteHeader();
begin
  while (FileExists(Filename) and not DeleteFile(Filename)) do
    DoError(SysError(), nil, True);

  inherited;
end;

{ TTTransfer.TItem ************************************************************}

constructor TTTransfer.TItem.Create(const AItems: TTool.TItems; const ADBObject: TSDBObject);
begin
  inherited;

  DestinationDatabaseName := '';
end;

{ TTTransfer ******************************************************************}

procedure TTTransfer.Add(const ADBObject: TSDBObject; const DestinationDatabaseName: string);
var
  NewItem: TItem;
begin
  NewItem := TItem.Create(Items, ADBObject);
  NewItem.DestinationDatabaseName := DestinationDatabaseName;

  Items.Add(NewItem);
end;

procedure TTTransfer.AfterExecute();
var
  SQL: string;
begin
  if (Data and (DestinationSession.ServerVersion >= 40014)) then
  begin
    SQL := 'SET UNIQUE_CHECKS=' + OLD_UNIQUE_CHECKS + ', FOREIGN_KEY_CHECKS=' + OLD_FOREIGN_KEY_CHECKS + ';' + #13#10;
    while ((Success <> daRetry) and not DestinationSession.ExecuteSQL(SQL)) do
      DoError(DatabaseError(DestinationSession), nil, True, SQL);
  end;

  DestinationSession.EndSilent();
  DestinationSession.EndSynchron();

  inherited AfterExecute();
end;

procedure TTTransfer.BeforeExecute();
var
  DataSet: TMySQLQuery;
  SQL: string;
begin
  inherited;

  DestinationSession.BeginSilent();
  DestinationSession.BeginSynchron(); // We're still in a thread

  if (Data and (DestinationSession.ServerVersion >= 40014)) then
  begin
    if (Assigned(DestinationSession.VariableByName('UNIQUE_CHECKS'))
      and Assigned(DestinationSession.VariableByName('FOREIGN_KEY_CHECKS'))) then
    begin
      OLD_UNIQUE_CHECKS := DestinationSession.VariableByName('UNIQUE_CHECKS').Value;
      OLD_FOREIGN_KEY_CHECKS := DestinationSession.VariableByName('FOREIGN_KEY_CHECKS').Value;
    end
    else
    begin
      DataSet := TMySQLQuery.Create(nil);
      DataSet.Connection := DestinationSession;
      DataSet.CommandText := 'SELECT @@UNIQUE_CHECKS, @@FOREIGN_KEY_CHECKS';

      while ((Success <> daAbort) and not DataSet.Active) do
      begin
        DataSet.Open();
        if (DestinationSession.ErrorCode > 0) then
          DoError(DatabaseError(DestinationSession), nil, True, SQL);
      end;

      if (DataSet.Active) then
      begin
        OLD_UNIQUE_CHECKS := DataSet.Fields[0].AsString;
        OLD_FOREIGN_KEY_CHECKS := DataSet.Fields[1].AsString;
        DataSet.Close();
      end;

      DataSet.Free();
    end;

    SQL := 'SET UNIQUE_CHECKS=0, FOREIGN_KEY_CHECKS=0;';
    while ((Success <> daAbort) and not DestinationSession.ExecuteSQL(SQL)) do
      DoError(DatabaseError(DestinationSession), nil, True, SQL);
  end;
end;

constructor TTTransfer.Create(const ASourceSession, ADestinationSession: TSSession);
begin
  inherited Create(ASourceSession);

  FDestinationSession := ADestinationSession;
end;

function TTTransfer.DoExecuteSQL(const Session: TSSession; var SQL: string): Boolean;
begin
  Result := (Success = daSuccess) and Session.ExecuteSQL(SQL);
  Delete(SQL, 1, Session.ExecutedSQLLength);
  SQL := SysUtils.Trim(SQL);
end;

procedure TTTransfer.ExecuteTable(const Item: TTool.TDBObjectItem; const DataHandle: TMySQLConnection.TDataResult);
var
  I: Integer;
  DestinationDatabase: TSDatabase;
  DestinationTable: TSBaseTable;
  NewTrigger: TSTrigger;
  SourceDatabase: TSDatabase;
  SourceTable: TSBaseTable;
begin
  DestinationDatabase := DestinationSession.DatabaseByName(TItem(Item).DestinationDatabaseName);

  if (Session = DestinationSession) then
  begin
    while ((Success <> daAbort) and not DestinationDatabase.CloneTable(TSBaseTable(Item.DBObject), Item.DBObject.Name, Data)) do
      DoError(DatabaseError(Session), Item, True);

    if ((Success = daSuccess) and Data) then
    begin
      Item.RecordsSum := TSBaseTable(Item.DBObject).CountRecords();
      Item.RecordsDone := Item.RecordsSum;
    end;
  end
  else
  begin
    if (Structure and not Assigned(DestinationDatabase)) then
    begin
      DestinationDatabase := TSDatabase.Create(DestinationSession, TItem(Item).DestinationDatabaseName);
      while ((Success <> daAbort) and not DestinationSession.AddDatabase(DestinationDatabase)) do
        DoError(DatabaseError(DestinationSession), Item, True);
      DestinationDatabase.Free();

      DestinationDatabase := DestinationSession.DatabaseByName(TItem(Item).DestinationDatabaseName);
    end;

    if (Success = daSuccess) then
    begin
      SourceTable := TSBaseTable(Item.DBObject);
      DestinationTable := DestinationDatabase.BaseTableByName(SourceTable.Name);

      if (Structure and Data and not Assigned(DestinationTable) and (Session = DestinationSession)) then
      begin
        while ((Success <> daAbort) and not DestinationDatabase.CloneTable(SourceTable, SourceTable.Name, True)) do
          DoError(DatabaseError(DestinationSession), Item, True);

        if (Success = daSuccess) then
        begin
          DestinationTable := DestinationDatabase.BaseTableByName(SourceTable.Name);

          Item.RecordsDone := DestinationTable.Rows;
        end;
      end
      else
      begin
        if ((Success = daSuccess) and Structure) then
        begin
          ExecuteTableStructure(TItem(Item));
          DestinationTable := DestinationDatabase.BaseTableByName(SourceTable.Name);

          if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
            Success := daAbort;
        end;

        if ((Success = daSuccess) and Data and Assigned(DestinationTable) and (DestinationTable.Source <> '')) then
          ExecuteTableData(TItem(Item), DataHandle);
      end;

      if (Success = daSuccess) then
        Item.RecordsSum := Item.RecordsDone;

      SourceDatabase := Item.DBObject.Database;
      SourceTable := TSBaseTable(Item.DBObject);
      if (Assigned(SourceDatabase.Triggers) and Assigned(DestinationDatabase.Triggers)) then
        for I := 0 to SourceDatabase.Triggers.Count - 1 do
          if ((Success = daSuccess) and (SourceDatabase.Triggers[I].Table = SourceTable) and not Assigned(DestinationDatabase.TriggerByName(SourceDatabase.Triggers[I].Name))) then
          begin
            NewTrigger := TSTrigger.Create(DestinationDatabase.Tables);
            NewTrigger.Assign(SourceDatabase.Triggers[I]);
            while (Success <> daAbort) do
            begin
              DestinationDatabase.AddTrigger(NewTrigger);
              if (DestinationSession.ErrorCode <> 0) then
                DoError(DatabaseError(DestinationSession), Item, True);
            end;
            NewTrigger.Free();
          end;
    end;
  end;

  Item.Done := Success = daSuccess;
  DoUpdateGUI();
end;

procedure TTTransfer.ExecuteTableData(const Item: TItem; const DataHandle: TMySQLConnection.TDataResult);
var
  Buffer: TTool.TStringBuffer;
  DataFileBuffer: TDataFileBuffer;
  DestinationDatabase: TSDatabase;
  DestinationField: TSTableField;
  DestinationTable: TSBaseTable;
  EscapedFieldName: array of string;
  EscapedTableName: string;
  FieldCount: Integer;
  FieldInfo: TFieldInfo;
  FilenameP: array [0 .. MAX_PATH] of Char;
  I: Integer;
  InsertStmtInSQL: Boolean;
  J: Integer;
  LibLengths: MYSQL_LENGTHS;
  LibRow: MYSQL_ROW;
  Pipe: THandle;
  Pipename: string;
  S: string;
  SourceDataSet: TMySQLQuery;
  SourceTable: TSBaseTable;
  SourceValues: string;
  SQL: string;
  SQLExecuted: TEvent;
  SQLExecuteLength: Integer;
  WrittenSize: Cardinal;
  Values: string;
begin
  SourceValues := ''; FilenameP[0] := #0;
  SourceTable := TSBaseTable(Item.DBObject);
  DestinationDatabase := DestinationSession.DatabaseByName(Item.DestinationDatabaseName);
  DestinationTable := DestinationDatabase.BaseTableByName(SourceTable.Name);

  FieldCount := 0;
  for I := 0 to SourceTable.Fields.Count - 1 do
    for J := 0 to DestinationTable.Fields.Count - 1 do
      if (lstrcmpi(PChar(SourceTable.Fields[I].Name), PChar(DestinationTable.Fields[J].Name)) = 0) then
        Inc(FieldCount);

  if ((Success = daSuccess) and (FieldCount > 0)) then
  begin
    SourceDataSet := TMySQLQuery.Create(nil);
    SourceDataSet.Open(DataHandle);
    while ((Success <> daRetry) and not SourceDataSet.Active) do
    begin
      SourceDataSet.Open();
      if (Session.ErrorCode > 0) then
        DoError(DatabaseError(Session), Item, True, SQL);
    end;

    if ((Success = daSuccess) and not SourceDataSet.IsEmpty()) then
    begin
      SQLExecuted := TEvent.Create(nil, False, False, '');

      if (DestinationSession.DataFileAllowed) then
      begin
        Pipename := '\\.\pipe\' + LoadStr(1000);
        Pipe := CreateNamedPipe(PChar(Pipename),
                                PIPE_ACCESS_OUTBOUND, PIPE_TYPE_MESSAGE or PIPE_READMODE_BYTE or PIPE_WAIT,
                                1, 2 * NET_BUFFER_LENGTH, 0, 0, nil);
        if (Pipe = INVALID_HANDLE_VALUE) then
          DoError(SysError(), nil, False)
        else
        begin
          SQL := '';
          if (DestinationSession.Lib.LibraryType <> ltHTTP) then
            if (DestinationSession.ServerVersion < 40011) then
              SQL := SQL + 'BEGIN;' + #13#10
            else
              SQL := SQL + 'START TRANSACTION;' + #13#10;
          if ((DestinationSession.ServerVersion >= 40000) and DestinationTable.Engine.IsMyISAM) then
            SQL := SQL + 'ALTER TABLE ' + DestinationSession.EscapeIdentifier(DestinationTable.Name) + ' DISABLE KEYS;' + #13#10;
          if (DestinationDatabase.Name <> DestinationSession.DatabaseName) then
            SQL := SQL + DestinationDatabase.SQLUse();
          SQL := SQL + SQLLoadDataInfile(DestinationDatabase, False, Pipename, DestinationSession.Charset, DestinationDatabase.Name, DestinationTable.Name, '');
          if ((DestinationSession.ServerVersion >= 40000) and DestinationTable.Engine.IsMyISAM) then
            SQL := SQL + 'ALTER TABLE ' + DestinationSession.EscapeIdentifier(DestinationTable.Name) + ' ENABLE KEYS;' + #13#10;
          if (DestinationSession.Lib.LibraryType <> ltHTTP) then
            SQL := SQL + 'COMMIT;' + #13#10;

          DestinationSession.SendSQL(SQL, SQLExecuted);

          if (ConnectNamedPipe(Pipe, nil)) then
          begin
            DataFileBuffer := TDataFileBuffer.Create(DestinationSession.CodePage);

            repeat
              LibLengths := SourceDataSet.LibLengths;
              LibRow := SourceDataSet.LibRow;

              for I := 0 to DestinationTable.Fields.Count - 1 do
              begin
                DestinationField := DestinationTable.Fields[I];
                if (I > 0) then
                  DataFileBuffer.Write(PAnsiChar(',_'), 1); // Two characters are needed to instruct the compiler to give a pointer - but the first character should be placed in the file only
                if (not Assigned(LibRow^[I])) then
                  DataFileBuffer.Write(PAnsiChar('NULL'), 4)
                else if (BitField(SourceDataSet.Fields[I])) then
                  begin S := UInt64ToStr(SourceDataSet.Fields[I].AsLargeInt); DataFileBuffer.WriteData(PChar(S), Length(S)); end
                else if (DestinationTable.Fields[I].FieldType in BinaryFieldTypes) then
                  DataFileBuffer.WriteBinary(LibRow^[I], LibLengths^[I])
                else if (DestinationField.FieldType in TextFieldTypes) then
                  DataFileBuffer.WriteText(LibRow^[I], LibLengths^[I], Session.CodePage)
                else
                  DataFileBuffer.Write(LibRow^[I], LibLengths^[I], not (DestinationField.FieldType in NotQuotedFieldTypes));
              end;
              DataFileBuffer.Write(PAnsiChar(#10 + '_'), 1); // Two characters are needed to instruct the compiler to give a pointer - but the first character should be placed in the file only

              if (DataFileBuffer.Size > NET_BUFFER_LENGTH) then
                if (not WriteFile(Pipe, DataFileBuffer.Data^, DataFileBuffer.Size, WrittenSize, nil) or (Abs(WrittenSize) < DataFileBuffer.Size)) then
                  DoError(SysError(), nil, False)
                else
                 DataFileBuffer.Clear();

              Inc(Item.RecordsDone);
              if (Item.RecordsDone mod 100 = 0) then
                DoUpdateGUI();

              if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
                Success := daAbort;
            until ((Success <> daSuccess) or not SourceDataSet.FindNext());

            if (DataFileBuffer.Size > 0) then
              if (not WriteFile(Pipe, DataFileBuffer.Data^, DataFileBuffer.Size, WrittenSize, nil) or (Abs(WrittenSize) < DataFileBuffer.Size)) then
                DoError(SysError(), nil, False)
              else
                DataFileBuffer.Clear();

            if (not FlushFileBuffers(Pipe) or not WriteFile(Pipe, DataFileBuffer.Data^, 0, WrittenSize, nil) or not FlushFileBuffers(Pipe)) then
              DoError(SysError(), nil, False)
            else
            begin
              DoUpdateGUI();
              SQLExecuted.WaitFor(INFINITE);
            end;

            DisconnectNamedPipe(Pipe);

            if (DestinationSession.ErrorCode <> 0) then
              DoError(DatabaseError(DestinationSession), Item, False, SQL);

            DataFileBuffer.Free();
          end;

          CloseHandle(Pipe);
        end;
      end
      else
      begin
        SQL := ''; SQLExecuteLength := 0;

        InsertStmtInSQL := False;

        EscapedTableName := DestinationSession.EscapeIdentifier(DestinationTable.Name);
        SetLength(EscapedFieldName, DestinationTable.Fields.Count);
        for I := 0 to DestinationTable.Fields.Count - 1 do
           EscapedFieldName[I] := DestinationSession.EscapeIdentifier(DestinationTable.Fields[I].Name);

        if (DestinationSession.Lib.LibraryType <> ltHTTP) then
          if (DestinationSession.ServerVersion < 40011) then
            SQL := SQL + 'BEGIN;' + #13#10
          else
            SQL := SQL + 'START TRANSACTION;' + #13#10;
        SQL := SQL + 'LOCK TABLES ' + EscapedTableName + ' WRITE;' + #13#10;
        if ((DestinationSession.ServerVersion >= 40000) and DestinationTable.Engine.IsMyISAM) then
          SQL := SQL + 'ALTER TABLE ' + EscapedTableName + ' DISABLE KEYS;' + #13#10;

        if (DestinationDatabase.Name <> DestinationSession.DatabaseName) then
          SQL := SQL + DestinationDatabase.SQLUse();

        repeat
          if (not InsertStmtInSQL) then
          begin
            InsertStmtInSQL := True;

            SQL := SQL + 'INSERT INTO ' + EscapedTableName + ' VALUES (';
          end
          else
            SQL := SQL + ',(';
          Values := '';
          for I := 0 to SourceDataSet.FieldCount - 1 do
          begin
            if (I > 0) then Values := Values + ',';
            Values := Values + SourceDataSet.SQLFieldValue(SourceDataSet.Fields[I]);
          end;
          SQL := SQL + Values + ')';

          if (Length(SQL) - SQLExecuteLength >= SQLPacketSize) then
          begin
            if (InsertStmtInSQL) then
            begin
              SQL := SQL + ';' + #13#10;
              InsertStmtInSQL := False;
            end;

            if (SQLExecuteLength > 0) then
            begin
              SQLExecuted.WaitFor(INFINITE);
              Delete(SQL, 1, DestinationSession.ExecutedSQLLength);
              SQLExecuteLength := 0;
              if (DestinationSession.ErrorCode <> 0) then
                DoError(DatabaseError(DestinationSession), Item, False, SQL);
            end;

            if (SQL <> '') then
            begin
              DestinationSession.SendSQL(SQL, SQLExecuted);
              SQLExecuteLength := Length(SQL);
            end;
          end;

          Inc(Item.RecordsDone);
          if (Item.RecordsDone mod 100 = 0) then DoUpdateGUI();

          if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
          begin
            if (SQL <> '') then
              DestinationSession.Terminate();
            Success := daAbort;
          end;
        until ((Success <> daSuccess) or not SourceDataSet.FindNext());

        if ((Success = daSuccess) and (SQLExecuteLength > 0)) then
        begin
          SQLExecuted.WaitFor(INFINITE);
          Delete(SQL, 1, DestinationSession.ExecutedSQLLength);
          if (DestinationSession.ErrorCode <> 0) then
            DoError(DatabaseError(DestinationSession), Item, False, SQL);
        end;

        if (InsertStmtInSQL) then
          SQL := SQL + ';' + #13#10;
        if ((DestinationSession.ServerVersion >= 40000) and DestinationTable.Engine.IsMyISAM) then
          SQL := SQL + 'ALTER TABLE ' + EscapedTableName + ' ENABLE KEYS;' + #13#10;
        SQL := SQL + 'UNLOCK TABLES;' + #13#10;
        if (DestinationSession.Lib.LibraryType <> ltHTTP) then
          SQL := SQL + 'COMMIT;' + #13#10;

        while ((Success <> daAbort) and not DoExecuteSQL(DestinationSession, SQL)) do
          DoError(DatabaseError(DestinationSession), Item, True, SQL);
      end;

      if (Success <> daSuccess) then
      begin
        SQL := '';
        if ((DestinationSession.ServerVersion >= 40000) and DestinationTable.Engine.IsMyISAM) then
          SQL := SQL + 'ALTER TABLE ' + EscapedTableName + ' ENABLE KEYS;' + #13#10;
        SQL := SQL + 'UNLOCK TABLES;' + #13#10;
        if (DestinationSession.Lib.LibraryType <> ltHTTP) then
          SQL := SQL + 'ROLLBACK;' + #13#10;
        DoExecuteSQL(DestinationSession, SQL);
      end;

      SQLExecuted.Free();
    end;

    if (Success <> daAbort) then
      SourceDataSet.Free();
  end;
end;

procedure TTTransfer.ExecuteTableStructure(const Item: TItem);
var
  DestinationDatabase: TSDatabase;
  DestinationTable: TSBaseTable;
  I: Integer;
  J: Integer;
  Modified: Boolean;
  NewDestinationTable: TSBaseTable;
  OldFieldBefore: TSTableField;
  SourceDatabase: TSDatabase;
  SourceTable: TSBaseTable;
begin
  SourceDatabase := Item.DBObject.Database;
  SourceTable := TSBaseTable(Item.DBObject);
  DestinationDatabase := DestinationSession.DatabaseByName(TItem(Item).DestinationDatabaseName);
  DestinationTable := DestinationDatabase.BaseTableByName(SourceTable.Name);

  if (Assigned(DestinationTable)) then
    while ((Success <> daAbort) and not DestinationDatabase.DeleteObject(DestinationTable)) do
      DoError(DatabaseError(DestinationSession), Item, True);

  NewDestinationTable := TSBaseTable.Create(DestinationDatabase.Tables);
  NewDestinationTable.Assign(SourceTable);
  NewDestinationTable.Name := DestinationSession.ApplyIdentifierName(NewDestinationTable.Name);

  for I := 0 to NewDestinationTable.Keys.Count - 1 do
    NewDestinationTable.Keys[I].Name := DestinationSession.ApplyIdentifierName(NewDestinationTable.Keys[I].Name);
  for I := 0 to NewDestinationTable.Fields.Count - 1 do
    NewDestinationTable.Fields[I].Name := DestinationSession.ApplyIdentifierName(NewDestinationTable.Fields[I].Name);
  for I := NewDestinationTable.ForeignKeys.Count - 1 downto 0 do
    NewDestinationTable.ForeignKeys[I].Name := DestinationSession.ApplyIdentifierName(NewDestinationTable.ForeignKeys[I].Name);

  NewDestinationTable.AutoIncrement := 0;

  while ((Success <> daAbort) and not DestinationDatabase.AddTable(NewDestinationTable)) do
    DoError(DatabaseError(DestinationSession), Item, True);

  NewDestinationTable.Free();
end;

{ TTSearch.TItem **************************************************************}

constructor TTSearch.TItem.Create(const AItems: TTool.TItems);
begin
  inherited;

  DatabaseName := '';
  SetLength(FieldNames, 0);
  RecordsSum := 0;
  TableName := '';
end;

destructor TTSearch.TItem.Destroy();
begin
  SetLength(FieldNames, 0);

  inherited;
end;

{ TTSearch ********************************************************************}

procedure TTSearch.Add(const Table: TSBaseTable; const Field: TSTableField = nil);
var
  Found: Boolean;
  NewItem: TItem;
  I: Integer;
begin
  NewItem := TItem.Create(Items);

  NewItem.DatabaseName := Table.Database.Name;
  NewItem.TableName := Table.Name;

  if (Assigned(Field)) then
  begin
    Found := False;
    for I := 0 to Length(NewItem.FieldNames) - 1 do
      Found := Found or (NewItem.FieldNames[I] = Field.Name);
    if (not Found) then
    begin
      SetLength(NewItem.FieldNames, Length(NewItem.FieldNames) + 1);
      NewItem.FieldNames[Length(NewItem.FieldNames) - 1] := Field.Name;
    end;
  end;

  Items.Add(NewItem);
end;

procedure TTSearch.AfterExecute();
begin
  Session.EndSilent();
  Session.EndSynchron();

  inherited;
end;

procedure TTSearch.BackupTable(const Item: TItem; const Rename: Boolean = False);
var
  Database: TSDatabase;
  NewTableName: string;
  Table: TSBaseTable;
begin
  Database := Session.DatabaseByName(Item.DatabaseName);

  if (Assigned(Database)) then
  begin
    Table := Database.BaseTableByName(Item.TableName);
    if (Assigned(Table)) then
    begin
      NewTableName := Item.TableName + BackupExtension;

      if (Assigned(Database.BaseTableByName(NewTableName))) then
        while ((Success <> daAbort) and not Database.DeleteObject(Database.BaseTableByName(NewTableName))) do
          DoError(DatabaseError(Session), Item, True);

      if (Rename) then
        while (Success <> daAbort) do
        begin
          Database.RenameTable(Table, NewTableName);
          if (Session.ErrorCode <> 0) then
            DoError(DatabaseError(Session), Item, True)
        end
      else
        while ((Success <> daAbort) and not Database.CloneTable(Table, NewTableName, True)) do
          DoError(DatabaseError(Session), Item, True);
    end;
  end;
end;

procedure TTSearch.BeforeExecute();
begin
  inherited;

  Session.BeginSilent();
  Session.BeginSynchron(); // We're still in a thread
end;

constructor TTSearch.Create(const ASession: TSSession);
begin
  inherited Create();

  FSession := ASession;

  FOnSearched := nil;
end;

function TTSearch.DoExecuteSQL(const Session: TSSession; const Item: TItem; var SQL: string): Boolean;
begin
  Result := (Success = daSuccess) and Session.ExecuteSQL(SQL);
  Delete(SQL, 1, Session.ExecutedSQLLength);
  SQL := SysUtils.Trim(SQL);
end;

procedure TTSearch.Execute();
var
  Database: TSDatabase;
  I: Integer;
  J: Integer;
  Table: TSBaseTable;
begin
  {$IFDEF EurekaLog}
  try
  {$ENDIF}

  BeforeExecute();

  for I := 0 to Items.Count - 1 do
  begin
    if (Success = daSuccess) then
    begin
      Table := Session.DatabaseByName(TItem(Items[I]).DatabaseName).BaseTableByName(TItem(Items[I]).TableName);

      if (Length(TItem(Items[I]).FieldNames) = 0) then
      begin
        SetLength(TItem(Items[I]).FieldNames, Table.Fields.Count);
        for J := 0 to Table.Fields.Count - 1 do
          TItem(Items[I]).FieldNames[J] := Table.Fields[J].Name;
      end;

      if (Table.Rows >= 0) then
        TItem(Items[I]).RecordsSum := Table.Rows
      else
        TItem(Items[I]).RecordsSum := Table.CountRecords();

      DoUpdateGUI();
    end;
  end;

  for I := 0 to Items.Count - 1 do
  begin
    if (Success = daSuccess) then
    begin
      if ((Self is TTReplace) and TTReplace(Self).Backup) then
      begin
        BackupTable(TItem(Items[I]));
        if (Success = daFail) then Success := daSuccess;
      end;

      if (Success = daSuccess) then
      begin
        Database := Session.DatabaseByName(TItem(Items[I]).DatabaseName);
        Table := Database.BaseTableByName(TItem(Items[I]).TableName);

        if (RegExpr or (not WholeValue and not MatchCase)) then
          ExecuteDefault(TItem(Items[I]), Table)
        else if (WholeValue) then
          ExecuteWholeValue(TItem(Items[I]), Table)
        else
          ExecuteMatchCase(TItem(Items[I]), Table);
      end;

      TItem(Items[I]).Done := Success <> daAbort;
      if ((TItem(Items[I]).Done) and Assigned(FOnSearched)) then
        FOnSearched(TItem(Items[I]));

      if (Success = daFail) then Success := daSuccess;

      DoUpdateGUI();
    end;
  end;

  AfterExecute();

  {$IFDEF EurekaLog}
  except
    StandardEurekaNotify(GetLastExceptionObject(), GetLastExceptionAddress());
  end;
  {$ENDIF}
end;

procedure TTSearch.ExecuteDefault(const Item: TItem; const Table: TSBaseTable);
var
  Buffer: TStringBuffer;
  DataSet: TMySQLQuery;
  Fields: array of TField;
  Found: Boolean;
  I: Integer;
  J: Integer;
  NewValue: string;
  PerlRegEx: TPerlRegEx;
  SQL: string;
  Value: string;
  WhereClausel: string;
  UseIndexFields: Boolean;
begin
  if (Success = daSuccess) then
  begin
    if (not (Self is TTReplace) and not RegExpr) then
      SQL := 'COUNT(*)'
    else if (Length(Item.FieldNames) = Table.Fields.Count) then
      SQL := '*'
    else
    begin
      SQL := '';
      for I := 0 to Table.Fields.Count - 1 do
        if (Table.Fields[I].InPrimaryKey) then
        begin
          if (SQL <> '') then SQL := SQL + ',';
          SQL := SQL + Session.EscapeIdentifier(Table.Fields[I].Name);
        end
        else
          for J := 0 to Length(Item.FieldNames) - 1 do
            if (Item.FieldNames[J] = Table.Fields[I].Name) then
            begin
              if (SQL <> '') then SQL := SQL + ',';
              SQL := SQL + Session.EscapeIdentifier(Table.Fields[J].Name);
            end;
    end;

    WhereClausel := '';
    for I := 0 to Length(Item.FieldNames) - 1 do
    begin
      if (I > 0) then WhereClausel := WhereClausel + ' OR ';
      if (not RegExpr) then
        WhereClausel := WhereClausel + Session.EscapeIdentifier(Item.FieldNames[I]) + ' LIKE ' + SQLEscape('%' + FindText + '%')
      else
        WhereClausel := WhereClausel + Session.EscapeIdentifier(Item.FieldNames[I]) + ' REGEXP ' + SQLEscape(FindText);
    end;
    SQL := 'SELECT ' + SQL + ' FROM ' + Session.EscapeIdentifier(Item.DatabaseName) + '.' + Session.EscapeIdentifier(Item.TableName) + ' WHERE ' + WhereClausel;

    DataSet := TMySQLQuery.Create(nil);
    DataSet.Connection := Session;
    DataSet.CommandText := SQL;

    while ((Success <> daAbort) and not DataSet.Active) do
    begin
      DataSet.Open();
      if (not DataSet.Active) then
        DoError(DatabaseError(Session), Item, True, SQL);
    end;

    if (Success = daSuccess) then
    begin
     if (DataSet.IsEmpty()) then
        Item.RecordsFound := 0
      else if (not (Self is TTReplace) and not RegExpr) then
        Item.RecordsFound := DataSet.Fields[0].AsInteger
      else
      begin
        SetLength(Fields, 0);
        for I := 0 to Length(Item.FieldNames) - 1 do
          if (Assigned(DataSet.FindField(Item.FieldNames[I]))) then
          begin
            SetLength(Fields, Length(Fields) + 1);
            Fields[Length(Fields) - 1] := DataSet.FindField(Item.FieldNames[I]);
          end;

        if (not RegExpr) then
          PerlRegEx := nil
        else
        begin
          PerlRegEx := TPerlRegEx.Create();
          PerlRegEx.RegEx := UTF8Encode(FindText);
          if (MatchCase) then
            PerlRegEx.Options := PerlRegEx.Options - [preCaseLess]
          else
            PerlRegEx.Options := PerlRegEx.Options + [preCaseLess];
          PerlRegEx.Study();
          if (Self is TTReplace) then
            PerlRegEx.Replacement := UTF8Encode(TTReplace(Self).ReplaceText);
        end;

        UseIndexFields := False;
        if (not (Self is TTReplace)) then
          Buffer := nil
        else
        begin
          TTReplace(Self).ReplaceConnection.StartTransaction();

          Buffer := TStringBuffer.Create(SQLPacketSize);

          if (Item.DatabaseName <> TTReplace(Self).ReplaceConnection.DatabaseName) then
            Buffer.Write(TTReplace(Self).ReplaceConnection.SQLUse(Item.DatabaseName));

          for I := 0 to DataSet.FieldCount - 1 do
            UseIndexFields := UseIndexFields or Fields[I].IsIndexField;
        end;

        repeat
          Found := False; SQL := '';
          for I := 0 to Length(Fields) - 1 do
            if (Assigned(DataSet.LibRow^[Fields[I].FieldNo - 1])) then
            begin
              Value := DataSet.GetAsString(Fields[I]);

              if (not (Self is TTReplace)) then
                if (not RegExpr) then
                  // will never occur, since without RegExpr COUNT(*) will be used
                else
                begin
                  // not MatchCase, since otherwise ExecuteMatchCase will be used
                  PerlRegEx.Subject := UTF8Encode(Value);
                  Found := Found or PerlRegEx.Match();
                end
              else
              begin
                if (not RegExpr) then
                begin
                  // not MatchCase, since otherwise ExecuteMatchCase will be used
                  NewValue := StringReplace(Value, FindText, TTReplace(Self).ReplaceText, [rfReplaceAll, rfIgnoreCase]);
                  Found := NewValue <> Value;
                end
                else
                begin
                  PerlRegEx.Subject := UTF8Encode(Value);
                  Found := PerlRegEx.ReplaceAll();
                  if (Found) then
                    NewValue := UTF8ToWideString(PerlRegEx.Subject);
                end;

                if (Found) then
                begin
                  if (SQL <> '') then SQL := SQL + ',';
                  SQL := SQL + Session.EscapeIdentifier(Fields[I].FieldName) + '=';
                  if (BitField(Fields[I])) then
                    SQL := SQL + NewValue
                  else if (Fields[I].DataType in NotQuotedDataTypes + [ftTimestamp]) then
                    SQL := SQL + NewValue
                  else if (Fields[I].DataType in [ftDate, ftDateTime, ftTime]) then
                    SQL := SQL + '''' + NewValue + ''''
                  else
                    SQL := SQL + SQLEscape(NewValue);
                end;
              end;
            end;

          if (not (Self is TTReplace)) then
          begin
            if (Found) then
              Inc(Item.RecordsFound);
          end
          else
            if (SQL <> '') then
            begin
              Inc(Item.RecordsFound);

              SQL := 'UPDATE ' + Session.EscapeIdentifier(Item.TableName) + ' SET ' + SQL + ' WHERE ';
              Found := False;
              for I := 0 to Length(Fields) - 1 do
                if (not UseIndexFields or Fields[I].IsIndexField) then
                begin
                  if (Found) then SQL := SQL + ' AND ';
                  SQL := SQL + Session.EscapeIdentifier(Fields[I].FieldName) + '=';
                  if (not Assigned(DataSet.LibRow^[I])) then
                    SQL := SQL + 'NULL'
                  else if (BitField(Fields[I])) then
                    SQL := SQL + 'b''' + Fields[I].AsString + ''''
                  else if (Fields[I].DataType in NotQuotedDataTypes + [ftTimestamp]) then
                    SQL := SQL + DataSet.GetAsString(Fields[I])
                  else if (Fields[I].DataType in [ftDate, ftDateTime, ftTime]) then
                    SQL := SQL + '''' + DataSet.GetAsString(Fields[I]) + ''''
                  else
                    SQL := SQL + SQLEscape(DataSet.GetAsString(Fields[I]));
                  Found := True;
                end;
              SQL := SQL + ';' + #13#10;

              Buffer.Write(SQL);

              if ((Buffer.Size > 0) and (not Session.MultiStatements or (Buffer.Size >= SQLPacketSize))) then
              begin
                SQL := Buffer.Read();
                DoExecuteSQL(TTReplace(Self).ReplaceConnection, Item, SQL);
                Buffer.Write(SQL);
              end;
            end;

          Inc(Item.RecordsDone);
          if (Item.RecordsDone mod 100 = 0) then DoUpdateGUI();

          if (UserAbort.WaitFor(IGNORE) = wrSignaled) then
            Success := daAbort;
        until ((Success <> daSuccess) or not DataSet.FindNext());

        if (Assigned(Buffer)) then
        begin
          if (Buffer.Size > 0) then
          begin
            SQL := Buffer.Read();
            DoExecuteSQL(TTReplace(Self).ReplaceConnection, Item, SQL);
          end;

          Buffer.Free();
        end;

        if (Self is TTReplace) then
        begin
          if (Success = daSuccess) then
            TTReplace(Self).ReplaceConnection.CommitTransaction()
          else
            TTReplace(Self).ReplaceConnection.RollbackTransaction();
        end;

        if (Assigned(PerlRegEx)) then
          PerlRegEx.Free();
      end;
    end;

    DataSet.Free();
  end;
end;

procedure TTSearch.ExecuteMatchCase(const Item: TItem; const Table: TSBaseTable);
var
  DataSet: TMySQLQuery;
  I: Integer;
  SQL: string;
begin
  SQL := '';
  for I := 0 to Length(Item.FieldNames) - 1 do
  begin
    if (I > 0) then SQL := SQL + ' OR ';
    SQL := SQL + 'BINARY(' + Session.EscapeIdentifier(Item.FieldNames[I]) + ') LIKE BINARY(' + SQLEscape('%' + FindText + '%') + ')';
  end;
  SQL := 'SELECT COUNT(*) FROM ' + Session.EscapeIdentifier(Table.Database.Name) + '.' + Session.EscapeIdentifier(Table.Name) + ' WHERE ' + SQL;

  DataSet := TMySQLQuery.Create(nil);
  DataSet.Connection := Session;
  DataSet.CommandText := SQL;
  while ((Success <> daAbort) and not DataSet.Active) do
  begin
    DataSet.Open();
    if (Session.ErrorCode > 0) then
      DoError(DatabaseError(Session), Item, True, SQL);
  end;

  if ((Success = daSuccess) and not DataSet.IsEmpty()) then
    Item.RecordsFound := DataSet.Fields[0].AsInteger;

  DataSet.Free();
end;

procedure TTSearch.ExecuteWholeValue(const Item: TItem; const Table: TSBaseTable);
var
  DataSet: TMySQLQuery;
  I: Integer;
  SQL: string;
begin
  SQL := '';
  for I := 0 to Length(Item.FieldNames) - 1 do
  begin
    if (I > 0) then SQL := SQL + ' OR ';
    if (MatchCase) then
      SQL := SQL + 'BINARY(' + Session.EscapeIdentifier(Item.FieldNames[I]) + ')=BINARY(' + SQLEscape(FindText) + ')'
    else
      SQL := SQL + Session.EscapeIdentifier(Item.FieldNames[I]) + '=' + SQLEscape(FindText)
  end;
  SQL := 'SELECT COUNT(*) FROM ' + Session.EscapeIdentifier(Table.Database.Name) + '.' + Session.EscapeIdentifier(Table.Name) + ' WHERE ' + SQL;

  DataSet := TMySQLQuery.Create(nil);
  DataSet.Connection := Session;
  DataSet.CommandText := SQL;

  while ((Success <> daAbort) and not DataSet.Active) do
  begin
    DataSet.Open();
    if (Session.ErrorCode > 0) then
      DoError(DatabaseError(Session), Item, True, SQL);
  end;

  if ((Success = daSuccess) and not DataSet.IsEmpty()) then
    Item.RecordsFound := DataSet.Fields[0].AsInteger;

  FreeAndNil(DataSet);

  if (Self is TTReplace) then
  begin
    SQL := '';
    if (Session.DatabaseName = Table.Database.Name) then
      SQL := SQL + Table.Database.SQLUse();

    for I := 0 to Length(Item.FieldNames) - 1 do
    begin
      SQL := SQL + 'UPDATE ' + Session.EscapeIdentifier(Table.Database.Name) + '.' + Session.EscapeIdentifier(Item.TableName);
      SQL := SQL + ' SET ' + Session.EscapeIdentifier(Item.FieldNames[I]) + '=' + SQLEscape(TTReplace(Self).ReplaceText);
      if (MatchCase) then
        SQL := SQL + ' WHERE BINARY(' + Session.EscapeIdentifier(Item.FieldNames[I]) + ')=BINARY(' + SQLEscape(FindText) + ')'
      else
        SQL := SQL + ' WHERE ' + Session.EscapeIdentifier(Item.FieldNames[I]) + '=' + SQLEscape(FindText);
      SQL := SQL + ';' + #13#10;
    end;

    while ((Success <> daAbort) and not DoExecuteSQL(TTReplace(Self).ReplaceConnection, Item, SQL)) do
      if (Session.ErrorCode = ER_TRUNCATED_WRONG_VALUE) then
      begin
        Delete(SQL, 1, Length(Session.CommandText));
        Success := daSuccess;
      end
      else
        DoError(DatabaseError(Session), Item, True, SQL);

    Item.RecordsDone := Item.RecordsSum;
  end;
end;

procedure TTSearch.DoUpdateGUI();
var
  I: Integer;
begin
  if (Assigned(OnUpdate)) then
  begin
    CriticalSection.Enter();

    ProgressInfos.TablesDone := 0;
    ProgressInfos.TablesSum := Items.Count;
    ProgressInfos.RecordsDone := 0;
    ProgressInfos.RecordsSum := 0;
    ProgressInfos.TimeDone := 0;
    ProgressInfos.TimeSum := 0;

    for I := 0 to Items.Count - 1 do
    begin
      if (TItem(Items[I]).Done) then
      begin
        Inc(ProgressInfos.TablesDone);
        Inc(ProgressInfos.RecordsDone, TItem(Items[I]).RecordsSum);
      end;

      Inc(ProgressInfos.RecordsSum, TItem(Items[I]).RecordsSum);
    end;

    ProgressInfos.TimeDone := Now() - StartTime;

    if ((ProgressInfos.RecordsDone = 0) and (ProgressInfos.TablesDone = 0)) then
    begin
      ProgressInfos.Progress := 0;
      ProgressInfos.TimeSum := 0;
    end
    else if (ProgressInfos.TablesDone < ProgressInfos.TablesSum) then
    begin
      ProgressInfos.Progress := Round(ProgressInfos.TablesDone / ProgressInfos.TablesSum * 100);
      ProgressInfos.TimeSum := ProgressInfos.TimeDone / ProgressInfos.TablesDone * ProgressInfos.TablesSum;
    end
    else
    begin
      ProgressInfos.Progress := 100;
      ProgressInfos.TimeSum := ProgressInfos.TimeDone;
    end;

    CriticalSection.Leave();

    OnUpdate(ProgressInfos);
  end;
end;

{ TTReplace *******************************************************************}

constructor TTReplace.Create(const ASession, AReplaceSession: TSSession);
begin
  inherited Create(ASession);

  FReplaceSession := AReplaceSession;
end;

procedure TTReplace.ExecuteMatchCase(const Item: TTSearch.TItem; const Table: TSBaseTable);
var
  I: Integer;
  SQL: string;
begin
  SQL := '';
  for I := 0 to Length(Item.FieldNames) - 1 do
  begin
    if (I > 0) then SQL := SQL + ',';
    SQL := SQL + Session.EscapeIdentifier(Item.FieldNames[I]) + '=REPLACE(' + Session.EscapeIdentifier(Item.FieldNames[I]) + ',' + SQLEscape(FindText) + ',' + SQLEscape(ReplaceText) + ')';
  end;
  SQL := 'UPDATE ' + Session.EscapeIdentifier(Item.DatabaseName) + '.' + Session.EscapeIdentifier(Item.TableName) + ' SET ' + SQL + ';';

  while ((Success <> daAbort) and not Session.ExecuteSQL(SQL)) do
    DoError(DatabaseError(Session), Item, True, SQL);

  Item.RecordsDone := Session.RowsAffected;
  Item.RecordsSum := Item.RecordsDone;
end;

{******************************************************************************}

var
  Driver: array [0 .. STR_LEN] of SQLTCHAR;
initialization
  ODBCDrivers := [];
  if (not SQL_SUCCEEDED(SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, @ODBCEnv))) then
    ODBCEnv := SQL_NULL_HANDLE
  else if (not SQL_SUCCEEDED(SQLSetEnvAttr(ODBCEnv, SQL_ATTR_ODBC_VERSION, SQLPOINTER(SQL_OV_ODBC3), SQL_IS_UINTEGER))) then
  begin
    SQLFreeHandle(SQL_HANDLE_ENV, ODBCEnv);
    ODBCEnv := SQL_NULL_HANDLE
  end 
  else if (SQL_SUCCEEDED(SQLDrivers(ODBCEnv, SQL_FETCH_FIRST, @Driver, Length(Driver), nil, nil, 0, nil))) then
    repeat
      if (lstrcmpi(PChar(@Driver), DriverAccess) = 0) then
        ODBCDrivers := ODBCDrivers + [odAccess]
      else if (lstrcmpi(PChar(@Driver), DriverAccess2007) = 0) then
        ODBCDrivers := ODBCDrivers + [odAccess2007]
      else if (lstrcmpi(PChar(@Driver), DriverExcel) = 0) then
        ODBCDrivers := ODBCDrivers + [odExcel]
      else if (lstrcmpi(PChar(@Driver), DriverExcel2007) = 0) then
        ODBCDrivers := ODBCDrivers + [odExcel2007];
    until (not SQL_SUCCEEDED(SQLDrivers(ODBCEnv, SQL_FETCH_NEXT, @Driver, Length(Driver), nil, nil, 0, nil)));
finalization
  if (ODBCEnv <> SQL_NULL_HANDLE) then
    SQLFreeHandle(SQL_HANDLE_ENV, ODBCEnv);
end.

