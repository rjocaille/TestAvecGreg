{
  Utilisation
  -----------

  Le module s'utilise principalement par l'intermédiaire du singleton de la classe
  principale: TAppStatistiques.Instance

  Pour automatiquement reprendre les statistiques d'utilisation d'un menu :
  Dans l'évênement OnShow de la fenêtre acceuillant le menu
  $DELPHI2007
      // Link du menu dans le module de statistiques
      TAppStatistiques.Instance.LinkMenu(MainMenu);
      // Définition du nom de l'application (peut être repris de Memvar.PGM_Name)
      TAppStatistiques.Instance.AppName := Memvar.PGM_Name;
      // Définition de l'ID de l'utilisateur
      TAppStatistiques.Instance.UserID := Memvar.m_userId;
      // NB: MemVar est volontairement découplé du module pour ne pas créer de dépendances
      ou
      // Link de tous les items de l'application avec définition optionnelle du nom de l'application et de l'ID de l'utilisateur
      TAppStatistiques.Instance.SearchAndLinkAllItems(Memvar.PGM_Name, Memvar.m_userId);
  $DELPHI2010
	  // Link du menu dans le module de statistiques
      AppStatistiques.LinkMenu(MainMenu);
      // Définition du nom de l'application (peut être repris de Memvar.PGM_Name)
      AppStatistiques.AppName := Memvar.PGM_Name;
      // Définition de l'ID de l'utilisateur
      AppStatistiques.UserID := Memvar.m_userId;
      // NB: MemVar est volontairement découplé du module pour ne pas créer de dépendances
      ou
      // Link de tous les items de l'application avec définition optionnelle du nom de l'application et de l'ID de l'utilisateur
      AppStatistiques.SearchAndLinkAllItems(Memvar.PGM_Name, Memvar.m_userId);

  Pour sauvegarder les statistiques et délier le module du menu :
  Dans l'évênement OnCLose de la fenêtre acceuillant le menu
      // On passe en paramètre l'ADOConnection de sorte à découpler le module de DM_APP
	$DELPHI2007
      TAppStatistiques.Instance.StoreToDBAndUnlinkItems(DMApp.ADconSQL);
	$DELPHI2010
      AppStatistiques.StoreToDBAndUnlinkItems(DMApp.ADconSQL);

  Pour logguer les clicks sur un bouton :
  Dans le OnClick du bouton, première instruction
	$DELPHI2007
      TAppStatistiques.Instance.LogAction('Mon bouton OK de l'écran X');
	$DELPHI2010
      AppStatistiques.LogAction('Mon bouton OK de l'écran X');

  Données en DB
  -------------

  Les données issues des statistiques sont sauvegardées en DB dans la table
  AppStatistiques du schéma dbo.
  On sauvegarde à chaque clôture d'application 1 ligne par menu item au moins cliqué
  une fois, pour autant que ce point de menu amène une action (donc pas les points de menu racines)
  On sauvegarde également 1 ligne par action item.
  Chaque ligne sauvegardée contient :
    - Nom de l'application
    - ID de l'utilisateur
    - Nom de l'item
    - Un boolean renseignant si il s'agit d'un item de type menu (ou action)
    - Le nombre d'ouvertures / click sur l'item durant la session
    - La durée moyenne à l'intérieur du menu sélectionné *
    - Le datetime du log de la ligne en DB

  Durée moyenne à l'intérieur du menu sélectionné
  -----------------------------------------------

  Cette durée est calculée par la différence entre le moment où on a clické sur
  le point de menu et le moment où on a cliqué sur le point de menu suivant.
  Si il n'y a plus de point de menu clické après, on prend le moment où le
  module a été clôturé.
}
unit L_AppStatistiques;

interface

uses
  Windows, Classes, Menus, SysUtils, Dialogs, Forms,
  DateUtils, ADODB, Variants;

type
  // Types d'items Menu ou Action
  TASTypes = (asMenu, asAction, asButton);
  TASTypesStrings = array [TASTypes] of String;
const
  ASTypesStrings: TASTypesStrings = ('Menu', 'Action', 'Button');

type
  // Classe ancêtre des items
  TASItem = class
  private
    FType: TASTypes;
    FName: String;
    FClickList: array of TDateTime;
    FTotalDuration: Cardinal;
    //
    procedure LogClick;
  end;

  // Item de type action
  TASActionItem = class(TASItem);

  // Item de type menu
  TASMenuItem = class(TASItem)
  private
    FMenuItem: TMenuItem;
    FOriginalEvent: TNotifyEvent;
    //
    procedure Unlink;
  public
    procedure OnClick(Sender: TObject);
  end;

  // Class gérant les satatistiques
  TAppStatistiques = class
{$IFDEF VER210}
  private
    class var FInstance: TAppStatistiques;
{$ENDIF}
  private
    FItemList: array of TASItem;
    FAppName: String;
    FUserID: String;
    FADOConnection: TADOConnection;
    //
    function AddNewMenuItem(const AMenuItem: TMenuItem; const AName: String): TASItem;
    function AddNewActionItem(const AActionName: String): TASItem;
    function GetActionItem(const AActionName: String): TASActionItem;
    procedure ComputeTotalDurations;
    function SQLExecuteWithTransaction(const ASql: String): Boolean;
    function SQLResult(ARequest: string; IsSelect:Boolean = true): Variant;
    procedure SetAppName(const AAppName: String);
    procedure SetUserID(const AUserID: String);
    procedure LinkMenuRecursive(const AMenuItem: TMenuItem; ParentPath: string);

    // Lier à un menu d'application
    procedure LinkMenu(const AMenu: TMenu);

{$IFDEF VER210}
  public
    class constructor Create;
    //
    class property Instance: TAppStatistiques read FInstance;
{$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;
    // Lier tous les items de l'application avec définition optionnelle du nom de l'application et de l'ID de l'utilisateur
    procedure SearchAndLinkAllItems(AppName: string = ''; UserID: string = '');
    // Sauvegarder les items encore non-utilisés en DB
    procedure StoreNotUsedItems(const AADOConnection: TADOConnection);
    // Délier du menu d'application
    procedure UnlinkMenu;
    // Sauvegarder les stats en DB puis délier les items d'application
    procedure StoreToDBAndUnlinkItems(const AADOConnection: TADOConnection);
    // Logguer une action (par exemple le click sur un bouton)
    procedure LogAction(const AActionName: String);
    // Nom de l'application à renseigner
    property AppName: String read FAppName write SetAppName;
    // ID de l'utilisateur à renseigner
    property UserID: String read FUserID write SetUserID;
  end;
 
{$IFNDEF VER210} 
var
  AppStatistiques : TAppStatistiques;
{$ENDIF}

implementation

function INSERT_NOT_USED_ITEM(const AAppName: String; const AUserID: String; const AItemName: String; const AEstMenuItem: Boolean; const AItemType: string): String;
begin
  Result := ' IF NOT EXISTS (Select 1 from AppStatistiques where AppName = ' + QuotedStr(AAppName) + ' and ItemName = ' + QuotedStr(AItemName) + ') ' +
    ' insert into AppStatistiques ' +
    ' (AppName, UserID, ItemName, EstMenuItem, ItemType, NbrOuvertures, DtLog) ' +
    ' values ' +
    ' (' + QuotedStr(AAppName) + ', ' + QuotedStr(AUserID) + ', ' + QuotedStr(AItemName) + ', ' + BoolToStr(AEstMenuItem) + ', ' + QuotedStr(AItemType) + ', ' +
    ' 0, GETDATE()) ';
end;

function INSERT_APPSTATISTIQUES(const AAppName: String; const AUserID: String; const AItemName: String; const AEstMenuItem: Boolean; const AItemType: string;
  const ANbrOuvertures: Integer; const ADureeMoyenneDedans: Integer): String;
begin
  Result :=
    ' insert into AppStatistiques ' +
    ' (AppName, UserID, ItemName, EstMenuItem, ItemType, NbrOuvertures, DureeMoyenneDedans, DtLog) ' +
    ' values ' +
    ' (' + QuotedStr(AAppName) + ', ' + QuotedStr(AUserID) + ', ' + QuotedStr(AItemName) + ', ' + BoolToStr(AEstMenuItem) + ', ' + QuotedStr(AItemType) + ', ' +
    ' ' + IntToStr(ANbrOuvertures) + ', ' + IntToStr(ADureeMoyenneDedans) + ', GETDATE()) ';
end;

function DELETE_NOT_USED_ITEM(const AAppName: String; const AItemName: String; const AItemType: string): String;
begin
  Result := ' IF (Select COUNT(*) from AppStatistiques where AppName = ' + QuotedStr(AAppName) + ' and ItemName = ' + QuotedStr(AItemName) + ' and ItemType = ' + QuotedStr(AItemType) + ') >= 2 ' +
    ' delete from AppStatistiques ' +
    ' where AppName = ' + QuotedStr(AAppName) + ' and ItemName = ' + QuotedStr(AItemName) + ' and ItemType = ' + QuotedStr(AItemType) + ' and NbrOuvertures = 0 ';
end;

{ TAppStatistiques }

constructor TAppStatistiques.Create;
begin
  FADOConnection := nil;
  SetLength(FItemList, 0);
  FAppName := '';
  FUserID := '';
end;

destructor TAppStatistiques.Destroy;
begin
  UnlinkMenu;
  inherited;
end;

function TAppStatistiques.AddNewMenuItem(const AMenuItem: TMenuItem; const AName: String): TASItem;
begin
  Result := TASMenuItem.Create;
  Result.FType := asMenu;
  Result.FName := AName;
  Result.FTotalDuration := 0;
  SetLength(Result.FClickList, 0);
  TASMenuItem(Result).FOriginalEvent := AMenuItem.OnClick;
  TASMenuItem(Result).FMenuItem := AMenuItem;
  AMenuItem.OnClick := TASMenuItem(Result).OnClick;
  //
  SetLength(FItemList, Length(FItemList)+1);
  FItemList[Length(FItemList)-1] := Result;
end;

function TAppStatistiques.AddNewActionItem(const AActionName: String): TASItem;
begin
  Result := TASActionItem.Create;
  Result.FType := asAction;
  Result.FName := AActionName;
  Result.FTotalDuration := 0;
  SetLength(Result.FClickList, 0);
  //
  SetLength(FItemList, Length(FItemList)+1);
  FItemList[Length(FItemList)-1] := Result;
end;

function TAppStatistiques.GetActionItem(const AActionName: String): TASActionItem;
var
  i: Integer;
begin
  Result := nil;
  if Length(FItemList) > 0 then
  begin
    for i := 0 to Length(FItemList) - 1 do
    begin
      if FItemList[i].FType = asAction then
      begin
        if FItemList[i].FName = AActionName then
        begin
//          Exit(TASActionItem(FItemList[i]));
          Result := TASActionItem(FItemList[i]);
          break;
        end;
      end;
    end;
  end;
end;

procedure TAppStatistiques.ComputeTotalDurations;
var
  i, j, k, l: Integer;
  dtMenuClick: TDateTime;
  currMenuClick: TDateTime;
  lastMenuClick: TDateTime;
  dtPlusProche: TDateTime;
begin
  lastMenuClick := Now;

  // Pour chaque menu
  if Length(FItemList) > 0 then
  begin
    for i := 0 to Length(FItemList) - 1 do
    begin
      if FItemList[i].FType = asMenu then
      begin
        // Pour chaque click dans le menu
        if Length(FItemList[i].FClickList) > 0 then
        begin
          for j := 0 to Length(FItemList[i].FClickList) - 1 do
          begin
            dtMenuClick := FItemList[i].FClickList[j];
            // Recherche du moment de clic suivant le plus proche
            dtPlusProche := lastMenuClick;
            //
            for k := 0 to Length(FItemList) - 1 do
            begin
              if FItemList[k].FType = asMenu then
              begin
                if Length(FItemList[k].FClickList) > 0 then
                begin
                  for l := 0 to Length(FItemList[k].FClickList) - 1 do
                  begin
                    currMenuClick := FItemList[k].FClickList[l];
                    // currMenuClick > dtMenuClick et dtPlusProche > currMenuClick
                    if ((CompareDateTime(currMenuClick, dtMenuClick) = 1) and
                       (CompareDateTime(dtPlusProche, currMenuClick) = 1)) then
                    begin
                      dtPlusProche := currMenuClick;
                    end;
                  end;
                end;
              end;
            end;
            //
            FItemList[i].FTotalDuration := FItemList[i].FTotalDuration + SecondsBetween(dtMenuClick, dtPlusProche);
          end;
        end;
      end;
    end;
  end;
end;
{$IFDEF VER210}
class constructor TAppStatistiques.Create;
begin
  FInstance := TAppStatistiques.Create;
end;
{$ENDIF}
procedure TAppStatistiques.SetAppName(const AAppName: String);
begin
  FAppName := AAppName;
end;

procedure TAppStatistiques.SetUserID(const AUserID: String);
begin
  FUserID := AUserID;
end;

function TAppStatistiques.SQLExecuteWithTransaction(const ASql: String): Boolean;
var
  ec: Integer;
begin
  // Ouvre une transaction avec un ADOConnection
  // Exécute les requêtes en une seule commande
  // Commit si tout ok
  // Rollback si exception ou si nouvelle erreur référencée dans le connecteur
  ec := FADOConnection.Errors.Count;
  FADOConnection.CommandTimeout := 10000;
  FADOConnection.BeginTrans;
  try
    FADOConnection.Execute(ASql);
    //
    if FADOConnection.Errors.Count > ec then
    begin
      raise Exception.Create('Error');
    end
    else
    begin
      FADOConnection.CommitTrans;
      Result := True;
    end;
  except
    FADOConnection.RollbackTrans;
    Result := False;
  end;
end;

function TAppStatistiques.SQLResult(ARequest: string; IsSelect:Boolean = true): Variant;
var
  ADOAppStatistiques: TADODataSet;
begin
  Result := Null;
  // fonction qui retourne UNE valeur d'une table SQL.
  // ou execute une commande avec un ADO pour recordset.
  if IsSelect then
  begin
    // c'est juste un select, il faut utiliser ADOAppStatistiques
    ADOAppStatistiques := TADODataSet.Create(nil);
    ADOAppStatistiques.Connection := FADOConnection;
    ADOAppStatistiques.CommandText := ARequest;
    ADOAppStatistiques.Open;
    if ADOAppStatistiques.RecordCount > 0 then
      Result := ADOAppStatistiques.Fields[0].Value;
    ADOAppStatistiques.Active := false;
    FreeAndNil(ADOAppStatistiques);
  end
  else
  begin
    // c'est une commande (Insert, update, ... )
    FADOConnection.Execute(ARequest);
  end;
end;

procedure TAppStatistiques.LinkMenu(const AMenu: TMenu);
var
  mi: TMenuItem;
  i: Integer;
  MenuPath: string;
  cSQL: string;
begin
  for i := 0 to AMenu.Items.Count - 1 do
  begin
    mi := AMenu.Items.Items[i];
    MenuPath := mi.Caption;

    AddNewMenuItem(mi, MenuPath);
//    ShowMessage(MenuPath);

    LinkMenuRecursive(mi, MenuPath);
  end;
end;

procedure TAppStatistiques.LinkMenuRecursive(const AMenuItem: TMenuItem; ParentPath: string); // ATTENTION: procedure récursive !!!
var
  mi: TMenuItem;
  i: Integer;
  MenuPath: string;
const
  MenuSeparator  = ' - ';
begin
  ParentPath := ParentPath + MenuSeparator;

  for i := 0 to AMenuItem.Count - 1 do
  begin
    mi := AMenuItem.Items[i];
    MenuPath := ParentPath + mi.Caption;

    AddNewMenuItem(mi, MenuPath);
//    ShowMessage(MenuPath);

    LinkMenuRecursive(mi, MenuPath);
  end;
end;

procedure TAppStatistiques.SearchAndLinkAllItems(AppName: string = ''; UserID: string = '');
var
  f: integer;
begin
  if AppName <> '' then
    SetAppName(AppName);
  if UserID <> '' then
    SetUserID(UserID);

  LinkMenu(Application.MainForm.Menu);

  // ...
end;

procedure TAppStatistiques.StoreNotUsedItems(const AADOConnection: TADOConnection);
var
  i: Integer;
  cSQL: String;
  cSQLRequest: string;
  AEstMenuItem: boolean;
begin
  try
    if not Assigned(FADOConnection) then
      FADOConnection := AADOConnection;

    cSQL := '';

    for i := 0 to Length(FItemList) - 1 do
    begin
      AEstMenuItem := false;
      if FItemList[i].FType = asMenu then
        AEstMenuItem := true;

      // On ajoute dans la table les items qui ne s'y trouvent pas encore ( = encore jamais utilisés)
      cSQL := cSQL + INSERT_NOT_USED_ITEM(FAppName, FUserID, FItemList[i].FName, AEstMenuItem, ASTypesStrings[FItemList[i].FType]);
    end;

    if cSQL <> '' then
    begin
      SQLResult(cSQL, false);
    end;
  finally
    // ...
  end;
end;

procedure TAppStatistiques.UnlinkMenu;
var
  i: Integer;
begin
  if Length(FItemList) > 0 then
  begin
    for i := 0 to Length(FItemList) - 1 do
    begin
      if FItemList[i].FType = asMenu then
      begin
        TASMenuItem(FItemList[i]).Unlink;
      end;
      FreeAndNil(FItemList[i]);
    end;
  end;
  SetLength(FItemList, 0);
end;

procedure TAppStatistiques.StoreToDBAndUnlinkItems(const AADOConnection: TADOConnection);
var
  i: Integer;
  cSQL: String;
  ItemType: string;
  AEstMenuItem: boolean;
begin
  if not Assigned(FADOConnection) then
    FADOConnection := AADOConnection;

  ComputeTotalDurations;
  try
    if Length(FItemList) > 0 then
    begin
      cSQL := '';
      //
      for i := 0 to Length(FItemList) - 1 do
      begin
        if Length(FItemList[i].FClickList) > 0 then
        begin
          ItemType := ASTypesStrings[FItemList[i].FType];

          AEstMenuItem := false;
          if FItemList[i].FType = asMenu then
            AEstMenuItem := true;

          cSQL := cSQL + INSERT_APPSTATISTIQUES(
            FAppName, FUserID, FItemList[i].FName, AEstMenuItem, ASTypesStrings[FItemList[i].FType],
            Length(FItemList[i].FClickList), FItemList[i].FTotalDuration div Length(FItemList[i].FClickList));

          // Pour l'item utilisé dans ce run, on supprime l'éventuel record qui indiquait que cet item n'était pas utilisé jusqu'à présent...
          cSQL := cSQL + DELETE_NOT_USED_ITEM(
            FAppName, FItemList[i].FName, ASTypesStrings[FItemList[i].FType]);
        end;
      end;
      //
      if cSQL <> '' then
      begin
        SQLExecuteWithTransaction(cSQL);
      end;
    end;
  finally
    StoreNotUsedItems(AADOConnection);
    UnlinkMenu;
  end;
end;

procedure TAppStatistiques.LogAction(const AActionName: String);
var
  actionItem: TASActionItem;
begin
  actionItem := GetActionItem(AActionName);
  if not Assigned(actionItem) then
  begin
    actionItem := TASActionItem(AddNewActionItem(AActionName));
  end;
  actionItem.LogClick;
end;

{ TASItem }

procedure TASItem.LogClick;
begin
  SetLength(FClickList, Length(FClickList) + 1);
  FClickList[Length(FClickList)-1] := Now;
end;

{ TASMenuItem }

procedure TASMenuItem.OnClick(Sender: TObject);
begin
  LogClick;
  if Assigned(FOriginalEvent) then
  begin
    FOriginalEvent(Sender);
  end;
end;

procedure TASMenuItem.Unlink;
begin
  if Assigned(FMenuItem) then
  begin
	try
      FMenuItem.OnClick := FOriginalEvent;
	except
	  // par le unit finalization, il se pourrait que le menu ait été détruit entre temps
	end;
  end;
end;

{$IFNDEF VER210} 
initialization
  AppStatistiques := TAppStatistiques.Create;
finalization
  FreeAndNil(AppStatistiques);
{$ENDIF}

end.
