{
  Copyright 2010-2017 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Setting up OpenGL shaders (TShader).Internal for CastleRenderer. @exclude }
unit CastleRendererInternalShader;

{$I castleconf.inc}

interface

uses Generics.Collections,
  CastleVectors, CastleGLShaders,
  X3DTime, X3DFields, X3DNodes, CastleUtils, CastleBoxes,
  CastleRendererInternalTextureEnv, CastleStringUtils, CastleShaders,
  CastleShapes;

type
  TSurfaceTexture = (stAmbient, stSpecular, stShininess);

  TTextureType = (tt2D, tt2DShadow, ttCubeMap, tt3D, ttShader);

  TTexGenerationComponent = (tgEye, tgObject);
  TTexGenerationComplete = (tgSphere, tgNormal, tgReflection);
  TTexComponent = 0..3;

  TFogCoordinateSource = (
    { Fog is determined by depth (distance to camera). }
    fcDepth,
    { Fog is determined by explicit coordinate (per-vertex glFogCoord*). }
    fcPassedCoordinate);

  TShaderCodeHash = record
  strict private
    Sum, XorValue: LongWord;
  public
    procedure AddString(const S: AnsiString; const Multiplier: LongWord);
    procedure AddInteger(const I: Integer);
    procedure AddFloat(const F: Single);
    procedure AddPointer(Ptr: Pointer);
    procedure AddEffects(Nodes: TX3DNodeList);

    function ToString: string;
    procedure Clear;

    class operator = (const A, B: TShaderCodeHash): boolean;
  end;

  { GLSL program that may be used by the X3D renderer.
    Provides some extra features, above the standard TGLSLProgram,
    but does not require to link the shader using TShader algorithm. }
  TX3DShaderProgramBase = class(TGLSLProgram)
  public
    { Uniforms initialized after linking.
      Initializing them only once after linking allows the mesh renderer to go fast. }
    UniformCastle_ModelViewMatrix,
    UniformCastle_ProjectionMatrix,
    UniformCastle_NormalMatrix,
    UniformCastle_MaterialDiffuseAlpha,
    UniformCastle_MaterialShininess,
    UniformCastle_SceneColor,
    UniformCastle_UnlitColor: TGLSLUniform;

    { Attributes initialized after linking.
      Initializing them only once after linking allows the mesh renderer to go fast. }
    AttributeCastle_Vertex,
    AttributeCastle_Normal,
    AttributeCastle_ColorPerVertex,
    AttributeCastle_FogCoord: TGLSLAttribute;

    procedure Link; override;
  end;

  { GLSL program integrated with VRML/X3D and TShader.
    Allows to bind uniform values from VRML/X3D fields,
    and to observe VRML/X3D events and automatically update uniform values.
    Also allows to initialize and check program by TShader.LinkProgram,
    and get a hash of it by TShader.CodeHash. }
  TX3DShaderProgram = class(TX3DShaderProgramBase)
  private
    { Events where we registered our EventReceive method. }
    EventsObserved: TX3DEventList;

    { Set uniform variable from VRML/X3D field value.
      Uniform name is contained in UniformName. UniformValue indicates
      uniform type and new value (UniformValue.Name is not used).

      Do not pass here SFNode / MFNode fields (these should be added to
      UniformsTextures).

      @raises(EGLSLUniformInvalid When uniform variable name
        or type are invalid.

        Caller should always catch this and change into WritelnWarning.

        X3D spec "OpenGL shading language (GLSL) binding" says
        "If the name is not available as a uniform variable in the
        provided shader source, the values of the node shall be ignored"
        (although it says when talking about "Vertex attributes",
        seems they mixed attributes and uniforms meaning in spec?).

        So invalid uniform names should be always catched.
        We also catch type mismatches.) }
    procedure SetUniformFromField(const UniformName: string;
      const UniformValue: TX3DField; const EnableDisable: boolean);

    procedure EventReceive(Event: TX3DEvent; Value: TX3DField;
      const Time: TX3DTime);

    { Set uniform shader variable from VRML/X3D field (exposed or not).
      We also start observing an exposed field or eventIn,
      and will automatically update uniform value when we receive an event. }
    procedure BindNonTextureUniform(
      const FieldOrEvent: TX3DInterfaceDeclaration;
      const EnableDisable: boolean);
  protected
    { Nodes that have interface declarations with textures for this shader. }
    UniformsTextures: TX3DFieldList;
  public
    constructor Create;
    destructor Destroy; override;

    { Set and observe uniform variables from given Node.InterfaceDeclarations.

      Non-texture fields are set immediately.
      Non-texture fields, and also events, become observed by this shader,
      and automatically updated when changed.

      Texture fields have to be updated by descendant (like TX3DGLSLProgram),
      using the UniformsTextures list. These methods add fields to this list.
      @groupBegin }
    procedure BindUniforms(const Node: TX3DNode; const EnableDisable: boolean);
    procedure BindUniforms(const Nodes: TX3DNodeList; const EnableDisable: boolean);
    { @groupEnd }
  end;

  TShader = class;

  TShaderSource = class
  private
    FSource: array [TShaderType] of TCastleStringList;
    function GetSource(const AType: TShaderType): TCastleStringList;
  public
    constructor Create;
    destructor Destroy; override;
    property Source [AType: TShaderType]: TCastleStringList read GetSource; default;

    { Append AppendCode to our code.
      Has some special features:

      - Doesn't use AppendCode[DontAppendFirstPart][0]
        (we use this for now only with texture and light shaders,
        which treat AppendCode[stVertex / stFragment][0] specially).

      - Doesn't add anything to given type, if it's already empty.
        For our internal base shaders, vertex and fragment are never empty.
        When they are empty, this means that user assigned ComposedShader,
        but depends on fixed-function pipeline to do part of the job. }
    procedure Append(AppendCode: TShaderSource; const DontAppendFirstPart: TShaderType);
  end;

  { Internal for TLightShader. @exclude }
  TLightDefine = (
    ldTypePosiional,
    ldTypeSpot,
    ldHasAttenuation,
    ldHasRadius,
    ldHasAmbient,
    ldHasSpecular,
    ldHasBeamWidth,
    ldHasSpotExponent);

  TLightShader = class
  private
    Number: Cardinal;
    Node: TAbstractLightNode;
    Light: PLightInstance;
    Shader: TShader;
    { Code calculated (on demand, when method called) using above vars. }
    FCode: TShaderSource;
    LightUniformName1: string;
    LightUniformValue1: Single;
    LightUniformName2: string;
    LightUniformValue2: Single;
    { Calculated by Prepare. Stored as TLightDefine array,
      since TLightShader.Prepare is executed very often and must be fast.
      Only TLightShader.Code actually changes it to a string. }
    Defines: array [0..9] of TLightDefine;
    DefinesCount: Cardinal;
  public
    destructor Destroy; override;
    { Prepare some stuff for Code generation, update Hash for this light shader. }
    procedure Prepare(var Hash: TShaderCodeHash; const LightNumber: Cardinal);
    function Code: TShaderSource;
    procedure SetUniforms(AProgram: TX3DShaderProgram);
    procedure SetDynamicUniforms(AProgram: TX3DShaderProgram);
  end;

  TLightShaders = class(specialize TObjectList<TLightShader>)
  private
    function Find(const Node: TAbstractLightNode; out Shader: TLightShader): boolean;
  end;

  { Setup the necessary shader things to pass texture coordinates. }
  TTextureCoordinateShader = class
  private
    TextureUnit: Cardinal;
    HasMatrixTransform: boolean;

    { Name of texture coordinate varying vec4 vector. }
    class function CoordName(const TexUnit: Cardinal): string;
    { Name of texture matrix mat4 uniform. }
    class function MatrixName(const TexUnit: Cardinal): string;
  public
    { Update Hash for this texture shader. }
    procedure Prepare(var Hash: TShaderCodeHash); virtual;
    procedure Enable(var TextureApply, TextureColorDeclare,
      TextureCoordInitialize, TextureCoordMatrix,
      TextureAttributeDeclare, TextureVaryingDeclare, TextureUniformsDeclare,
      GeometryVertexSet, GeometryVertexZero, GeometryVertexAdd: string); virtual;
  end;

  { Setup the necessary shader things to query a texture using texture coordinates. }
  TTextureShader = class(TTextureCoordinateShader)
  private
    TextureType: TTextureType;
    Node: TAbstractTextureNode;
    Env: TTextureEnv;
    ShadowMapSize: Cardinal;
    ShadowLight: TAbstractLightNode;
    ShadowVisualizeDepth: boolean;
    Shader: TShader;

    { Uniform to set for this texture. May be empty. }
    UniformName: string;
    UniformValue: LongInt;

    { Mix texture colors into fragment color, based on TTextureEnv specification. }
    class function TextureEnvMix(const AEnv: TTextureEnv;
      const FragmentColor, CurrentTexture: string;
      const ATextureUnit: Cardinal): string;
  public
    { Update Hash for this texture shader. }
    procedure Prepare(var Hash: TShaderCodeHash); override;
    procedure Enable(var TextureApply, TextureColorDeclare,
      TextureCoordInitialize, TextureCoordMatrix,
      TextureAttributeDeclare, TextureVaryingDeclare, TextureUniformsDeclare,
      GeometryVertexSet, GeometryVertexZero, GeometryVertexAdd: string); override;
  end;

  TTextureCoordinateShaderList = specialize TObjectList<TTextureCoordinateShader>;

  TBumpMapping = (bmNone, bmBasic, bmParallax, bmSteepParallax, bmSteepParallaxShadowing);

  TDynamicUniform = class abstract
  public
    Name: string;
    { Declaration to put at the top of the shader code.
      Must end with newline. May be empty if you do it directly yourself. }
    Declaration: string;
    procedure SetUniform(AProgram: TX3DShaderProgram); virtual; abstract;
  end;

  TDynamicUniformSingle = class(TDynamicUniform)
  public
    Value: Single;
    procedure SetUniform(AProgram: TX3DShaderProgram); override;
  end;

  TDynamicUniformVec3 = class(TDynamicUniform)
  public
    Value: TVector3;
    procedure SetUniform(AProgram: TX3DShaderProgram); override;
  end;

  TDynamicUniformVec4 = class(TDynamicUniform)
  public
    Value: TVector4;
    procedure SetUniform(AProgram: TX3DShaderProgram); override;
  end;

  TDynamicUniformMat4 = class(TDynamicUniform)
  public
    Value: TMatrix4;
    procedure SetUniform(AProgram: TX3DShaderProgram); override;
  end;

  TDynamicUniformList = specialize TObjectList<TDynamicUniform>;

  TSurfaceTextureShader = record
    Enable: boolean;
    TextureUnit, TextureCoordinatesId: Cardinal;
    ChannelMask: string;
    class function UniformTextureName(const SurfaceTexture: TSurfaceTexture): string; static;
  end;

  { Create appropriate shader and at the same time set OpenGL parameters
    for fixed-function rendering. Once everything is set up,
    you can create TX3DShaderProgram instance
    and initialize it by LinkProgram here, then enable it if you want.
    Or you can simply allow the fixed-function pipeline to work.

    This is used internally by TGLRenderer. It isn't supposed to be used
    directly by other code. }
  TShader = class
  private
    { When adding new field, remember to clear it in Clear method. }
    { List of effect nodes that determine uniforms of our program. }
    UniformsNodes: TX3DNodeList;
    TextureCoordGen, ClipPlane, FragmentEnd: string;
    FShadowSampling: TShadowSampling;
    Source: TShaderSource;
    PlugIdentifiers: Cardinal;
    LightShaders: TLightShaders;
    TextureShaders: TTextureCoordinateShaderList;
    FCodeHash: TShaderCodeHash;
    CodeHashFinalized: boolean;
    SelectedNode: TComposedShaderNode;
    WarnMissingPlugs: boolean;
    FShapeRequiresShaders: boolean;
    FBumpMapping: TBumpMapping;
    FNormalMapTextureCoordinatesId: Cardinal;
    FNormalMapTextureUnit: Cardinal;
    FHeightMapInAlpha: boolean;
    FHeightMapScale: Single;
    FSurfaceTextureShaders: array [TSurfaceTexture] of TSurfaceTextureShader;
    FFogEnabled: boolean;
    FFogType: TFogType;
    FFogColor: TVector3;
    FFogLinearEnd: Single;
    FFogExpDensity: Single;
    FFogCoordinateSource: TFogCoordinateSource;
    HasGeometryMain: boolean;
    DynamicUniforms: TDynamicUniformList;
    TextureMatrix: TCardinalList;
    NeedsCameraInverseMatrix: boolean;
    FPhongShading: boolean;

    { We have to optimize the most often case of TShader usage,
      when the shader is not needed or is already prepared.

      - Enabling shader features should not do anything time-consuming,
        as it's done every frame. This means that we cannot construct
        complete shader source code on the fly, as this would mean
        slowdown at every frame for every shape.
        So enabling a feature merely records the demand for this feature.

      - It must also set ShapeRequiresShaders := true, if needed.
      - It must also update FCodeHash, if needed (if final shader code or
        uniform value changes). Can be done immediately, or inside
        CodeHashFinalize (the latter is more comfortable if it may change
        repeatedly and you don't want temporary values to be added to hash).
      - Actually adding this feature to shader source may be done at LinkProgram.
    }
    AppearanceEffects: TMFNode;
    GroupEffects: TX3DNodeList;
    Lighting, MaterialFromColor: boolean;

    procedure EnableEffects(Effects: TMFNode;
      const Code: TShaderSource = nil;
      const ForwardDeclareInFinalShader: boolean = false);
    procedure EnableEffects(Effects: TX3DNodeList;
      const Code: TShaderSource = nil;
      const ForwardDeclareInFinalShader: boolean = false);

    { Special form of Plug. It inserts the PlugValue source code directly
      at the position of given plug comment (no function call
      or anything is added). It also assumes that PlugName occurs only once
      in the Code, for speed.

      Returns if plug code was inserted (always @true when
      InsertAtBeginIfNotFound). }
    function PlugDirectly(Code: TCastleStringList;
      const CodeIndex: Cardinal;
      const PlugName, PlugValue: string;
      const InsertAtBeginIfNotFound: boolean): boolean;

    { Make symbol DefineName to be defined for all GLSL parts of
      Source[ShaderType]. }
    procedure Define(const DefineName: string; const ShaderType: TShaderType);

    function DeclareShadowFunctions: string;
  public
    ShapeBoundingBox: TBox3D;

    { Collected material properties for current shape.
      Must be set before EnableLight, and be constant later --- this matters
      esp. for MaterialSpecular. }
    MaterialAmbient, MaterialDiffuse, MaterialSpecular, MaterialEmission: TVector4;
    MaterialShininessExp: Single;
    MaterialUnlit: TVector4;

    { Camera * scene transformation (without the shape transformation). }
    SceneModelView: TMatrix4;

    constructor Create;
    destructor Destroy; override;

    { Detect PLUG_xxx functions within PlugValue,
      look for matching @code(/* PLUG: xxx ...*/) declarations in both CompleteCode
      and the final shader source.

      For every plug declaration,
      @unorderedList(
        @item(insert the appropriate call to the plug function,)
        @item(and insert forward declaration of the plug function.)
      )

      Also, always insert the PlugValue (which should be variable and functions
      declarations) as another part of the CompleteCode.

      EffectPartType determines which type of CompleteCode is used.

      When CompleteCode = nil then we assume code of the final shader
      (private Source field).

      ForwardDeclareInFinalShader should be used only when Code is not nil.
      It means that forward declarations for Code[0] will be inserted
      into final shader code, not into Code[0]. This is useful if your
      Code[0] is special, and it will be pasted directly (not as plug)
      into final shader code.

      Inserts calls right before the magic @code(/* PLUG ...*/) comments,
      this way many Plug calls that defined the same PLUG_xxx function
      will be called in the same order.

      Doesn't do anything if in the final shader given type (EffectPartType)
      has empty code. This indicates that we used ComposedShader, and this type
      has no source code (so it should be done by fixed-function pipeline).
      Adding our own plug would be bad in this case, as we would create shader
      without main(). }
    procedure Plug(const EffectPartType: TShaderType; PlugValue: string;
      CompleteCode: TShaderSource = nil;
      const ForwardDeclareInFinalShader: boolean = false);

    { Add fragment and vertex shader code, link.
      @raises EGLSLError In case of troubles with linking. }
    procedure LinkProgram(AProgram: TX3DShaderProgram;
      const ShapeNiceName: string);

    { Add a fallback vertex + fragment shader code and link.
      Use this when normal LinkProgram failed, but you want to have
      *any* shader anyway.
      @raises EGLSLError In case of troubles with linking. }
    procedure LinkFallbackProgram(AProgram: TX3DShaderProgram);

    { Calculate the hash of all the current TShader settings,
      that is the hash of GLSL program code initialized by this shader
      LinkProgram. You should use this only when the GLSL program source
      is completely initialized (all TShader settings are set).

      It can be used to decide when the shader GLSL program needs
      to be regenerated, shared etc. }
    function CodeHash: TShaderCodeHash;

    procedure EnableTexture(const TextureUnit: Cardinal;
      const TextureType: TTextureType; const Node: TAbstractTextureNode;
      const Env: TTextureEnv;
      const ShadowMapSize: Cardinal = 0;
      const ShadowLight: TAbstractLightNode = nil;
      const ShadowVisualizeDepth: boolean = false);
    procedure EnableTexGen(const TextureUnit: Cardinal;
      const Generation: TTexGenerationComponent; const Component: TTexComponent;
      const Plane: TVector4);
    procedure EnableTexGen(const TextureUnit: Cardinal;
      const Generation: TTexGenerationComplete;
      const TransformToWorldSpace: boolean = false);
    { Disable fixed-function texgen of given texture unit.
      Guarantees to also set active texture unit to TexUnit (if multi-texturing
      available at all). }
    procedure DisableTexGen(const TextureUnit: Cardinal);
    procedure EnableTextureTransform(const TextureUnit: Cardinal;
      const Matrix: TMatrix4);
    procedure EnableClipPlane(const ClipPlaneIndex: Cardinal);
    procedure DisableClipPlane(const ClipPlaneIndex: Cardinal);
    procedure EnableAlphaTest;
    procedure EnableBumpMapping(const BumpMapping: TBumpMapping;
      const NormalMapTextureUnit, NormalMapTextureCoordinatesId: Cardinal;
      const HeightMapInAlpha: boolean; const HeightMapScale: Single);
    procedure EnableSurfaceTexture(const SurfaceTexture: TSurfaceTexture;
      const TextureUnit, TextureCoordinatesId: Cardinal;
      const ChannelMask: string);
    { Enable light source. Remember to set MaterialXxx before calling this. }
    procedure EnableLight(const Number: Cardinal; Light: PLightInstance);
    procedure EnableFog(const FogType: TFogType;
      const FogCoordinateSource: TFogCoordinateSource;
      const FogColor: TVector3; const FogLinearEnd: Single;
      const FogExpDensity: Single);
    { Modify some fog parameters, relevant only if fog already enabled.
      Used by FogCoordinate, that changes some fog settings,
      but does not change fog color.  }
    procedure ModifyFog(const FogType: TFogType;
      const FogCoordinateSource: TFogCoordinateSource;
      const FogLinearEnd: Single; const FogExpDensity: Single);
    function EnableCustomShaderCode(Shaders: TMFNodeShaders;
      out Node: TComposedShaderNode): boolean;
    procedure EnableAppearanceEffects(Effects: TMFNode);
    procedure EnableGroupEffects(Effects: TX3DNodeList);
    procedure EnableLighting;
    procedure EnableMaterialFromColor;

    property ShadowSampling: TShadowSampling
      read FShadowSampling write FShadowSampling;
    property ShapeRequiresShaders: boolean read FShapeRequiresShaders
      write FShapeRequiresShaders;

    { Clear instance, bringing it to the state after creation.
      You must call Intialize afterwards. }
    procedure Clear;

    { Initialize the instance and PhongShading.
      For now, PhongShading must be set early (and cannot be changed later),
      as it determines the initial shader templates that may be used before linking. }
    procedure Initialize(const APhongShading: boolean);

    property PhongShading: boolean read FPhongShading;

    { Set uniforms that should be set each time before using shader
      (because changes to their values may happen at any time,
      and they do not cause rebuilding the shader). }
    procedure SetDynamicUniforms(AProgram: TX3DShaderProgram);

    { Add a screen effect GLSL code. }
    procedure AddScreenEffectCode(const Depth: boolean);
  end;

implementation

uses SysUtils, StrUtils,
  {$ifdef CASTLE_OBJFPC} CastleGL, {$else} GL, GLExt, {$endif}
  CastleGLUtils, CastleLog, Castle3D, CastleGLVersion, CastleRenderingCamera,
  CastleScreenEffects, CastleInternalX3DLexer;

{ String helpers ------------------------------------------------------------- }

{ MoveTo do not warn about incorrect PLUG_ declarations, only return @false
  on them. That's because FindPlugName should just ignore them.
  But we log them --- maybe they will be useful
  in case there's some problem with FindPlugName. }

function MoveToOpeningParen(const S: string; var P: Integer): boolean;
begin
  Result := true;
  repeat
    Inc(P);

    if P > Length(S) then
    begin
      if Log then WritelnLog('VRML/X3D', 'PLUG declaration unexpected end (no opening parenthesis "(")');
      Exit(false);
    end;

    if (S[P] <> '(') and
       not (S[P] in WhiteSpaces) then
    begin
      if Log then WritelnLog('VRML/X3D', Format('PLUG declaration unexpected character "%s" (expected opening parenthesis "(")',
        [S[P]]));
      Exit(false);
    end;
  until S[P] = '(';
 end;

function MoveToMatchingParen(const S: string; var P: Integer): boolean;
var
  ParenLevel: Cardinal;
begin
  Result := true;
  ParenLevel := 1;

  repeat
    Inc(P);
    if P > Length(S) then
    begin
      if Log then WritelnLog('VRML/X3D', 'PLUG declaration unexpected end (no closing parenthesis ")")');
      Exit(false);
    end;

    if S[P] = '(' then
      Inc(ParenLevel) else
    if S[P] = ')' then
      Dec(ParenLevel);
  until ParenLevel = 0;
end;

{ TShaderCodeHash ------------------------------------------------------------ }

{$include norqcheckbegin.inc}

procedure TShaderCodeHash.AddString(const S: AnsiString; const Multiplier: LongWord);
var
  PS: PLongWord;
  Last: LongWord;
  I: Integer;
begin
  PS := PLongWord(S);

  for I := 1 to Length(S) div 4 do
  begin
    Sum += PS^ * Multiplier;
    XorValue := XorValue xor PS^;
    Inc(PS);
  end;

  if Length(S) mod 4 <> 0 then
  begin
    Last := 0;
    Move(S[(Length(S) div 4) * 4 + 1], Last, Length(S) mod 4);
    Sum += Last * Multiplier;
    XorValue := XorValue xor Last;
  end;
end;

procedure TShaderCodeHash.AddPointer(Ptr: Pointer);
begin
  { This will cut the pointer on non-32bit processors.
    But that's not a problem --- we just want it for hash,
    taking the least significant 32 bits from pointer is OK for this. }
  Sum += LongWord(PtrUInt(Ptr));
  XorValue := XorValue xor LongWord(PtrUInt(Ptr));
end;

procedure TShaderCodeHash.AddInteger(const I: Integer);
begin
  Sum += I;
end;

procedure TShaderCodeHash.AddFloat(const F: Single);
begin
  Sum += Round(F * 100000);
end;

{$include norqcheckend.inc}

procedure TShaderCodeHash.AddEffects(Nodes: TX3DNodeList);
var
  I: Integer;
begin
  { We add to hash actual Effect node references (pointers), this way ensuring
    that to share the same shader, effect nodes must be the same.
    Merely equal GLSL source code is not enough (because effects with equal
    source code may still have different uniform values, and sharing them
    would not be handled correctly here --- we set uniform values on change,
    not every time before rendering shape). }
  for I := 0 to Nodes.Count - 1 do
    if (Nodes[I] is TEffectNode) and
       TEffectNode(Nodes[I]).FdEnabled.Value then
      AddPointer(Nodes[I]);
end;

function TShaderCodeHash.ToString: string;
begin
  Result := IntToStr(Sum) + '/' + IntToStr(XorValue);
end;

procedure TShaderCodeHash.Clear;
begin
  Sum := 0;
  XorValue := 0;
end;

class operator TShaderCodeHash.= (const A, B: TShaderCodeHash): boolean;
begin
  Result := (A.Sum = B.Sum) and (A.XorValue = B.XorValue);
end;

{ TShaderSource -------------------------------------------------------------- }

constructor TShaderSource.Create;
var
  SourceType: TShaderType;
begin
  inherited;
  for SourceType := Low(SourceType) to High(SourceType) do
    FSource[SourceType] := TCastleStringList.Create;
end;

destructor TShaderSource.Destroy;
var
  SourceType: TShaderType;
begin
  for SourceType := Low(SourceType) to High(SourceType) do
    FreeAndNil(FSource[SourceType]);
  inherited;
end;

function TShaderSource.GetSource(const AType: TShaderType): TCastleStringList;
begin
  Result := FSource[AType];
end;

procedure TShaderSource.Append(AppendCode: TShaderSource; const DontAppendFirstPart: TShaderType);
var
  T: TShaderType;
  I: Integer;
begin
  for T := Low(T) to High(T) do
    if Source[T].Count <> 0 then
      for I := Iff(T = DontAppendFirstPart, 1, 0) to AppendCode[T].Count - 1 do
        Source[T].Add(AppendCode[T][I]);
end;

{ TLightShader --------------------------------------------------------------- }

destructor TLightShader.Destroy;
begin
  FreeAndNil(FCode);
  inherited;
end;

const
  LightDefines: array [TLightDefine] of record
    Name: string;
    Hash: LongWord;
  end =
  ( (Name: 'LIGHT_TYPE_POSITIONAL'  ; Hash: 107; ),
    (Name: 'LIGHT_TYPE_SPOT'        ; Hash: 109; ),
    (Name: 'LIGHT_HAS_ATTENUATION'  ; Hash: 113; ),
    (Name: 'LIGHT_HAS_RADIUS'       ; Hash: 127; ),
    (Name: 'LIGHT_HAS_AMBIENT'      ; Hash: 131; ),
    (Name: 'LIGHT_HAS_SPECULAR'     ; Hash: 137; ),
    (Name: 'LIGHT_HAS_BEAM_WIDTH'   ; Hash: 139; ),
    (Name: 'LIGHT_HAS_SPOT_EXPONENT'; Hash: 149; )
  );

procedure TLightShader.Prepare(var Hash: TShaderCodeHash; const LightNumber: Cardinal);

  procedure Define(const D: TLightDefine);
  begin
    Assert(DefinesCount <= High(Defines), 'Too many light #defines, increase High(TLightShader.Defines)');
    Defines[DefinesCount] := D;
    Inc(DefinesCount);
    Hash.AddInteger(LightDefines[D].Hash * (LightNumber + 1));
  end;

begin
  DefinesCount := 0;
  Hash.AddInteger(101);

  if Node is TAbstractPositionalLightNode then
  begin
    Define(ldTypePosiional);
    if Node is TSpotLightNode_1 then
    begin
      Define(ldTypeSpot);
      if TSpotLightNode_1(Node).SpotExponent <> 0 then
        Define(ldHasSpotExponent);
    end else
    if Node is TSpotLightNode then
    begin
      Define(ldTypeSpot);
      if TSpotLightNode(Node).FdBeamWidth.Value <
         TSpotLightNode(Node).FdCutOffAngle.Value then
      begin
        Define(ldHasBeamWidth);
        LightUniformName1 := 'castle_LightSource%dBeamWidth';
        LightUniformValue1 := TSpotLightNode(Node).FdBeamWidth.Value;
        Hash.AddFloat(LightUniformValue1);
      end;
    end;

    if TAbstractPositionalLightNode(Node).HasAttenuation then
      Define(ldHasAttenuation);

    if TAbstractPositionalLightNode(Node).HasRadius and
      { Do not activate per-pixel checking of light radius,
        if we know (by bounding box test below)
        that the whole shape is completely within radius. }
      (Shader.ShapeBoundingBox.PointMaxDistance(Light^.Location, -1) > Light^.Radius) then
    begin
      Define(ldHasRadius);
      LightUniformName2 := 'castle_LightSource%dRadius';
      LightUniformValue2 := Light^.Radius;
      { Uniform value comes from this Node's property,
        so this cannot be shared with other light nodes,
        that may have not synchronized radius value.

        (Note: We could instead add radius value to the hash.
        Then this shader could be shared between all light nodes with
        the same radius value --- however, if radius changed,
        then the shader would have to be recreated, even if the same
        light node was used.) }
      Hash.AddPointer(Node);
    end;
  end;
  if Node.FdAmbientIntensity.Value <> 0 then
    Define(ldHasAmbient);
  if not ( (Shader.MaterialSpecular[0] = 0) and
           (Shader.MaterialSpecular[1] = 0) and
           (Shader.MaterialSpecular[2] = 0)) then
    Define(ldHasSpecular);
end;

function TLightShader.Code: TShaderSource;

  { Convert Defines list into a string of GLSL code. }
  function DefinesStr: string;
  var
    I: Integer;
  begin
    Result := '';
    for I := 0 to DefinesCount - 1 do
      Result += '#define ' + LightDefines[Defines[I]].Name + NL;
  end;

var
  TemplateLight: string;
  LightingStage: TShaderType;
begin
  if FCode = nil then
  begin
    FCode := TShaderSource.Create;

    TemplateLight := {$I template_light.glsl.inc};
    TemplateLight := StringReplace(TemplateLight,
      '<Light>', IntToStr(Number), [rfReplaceAll]);

    if Shader.PhongShading then
      LightingStage := stFragment
    else
      LightingStage := stVertex;
    FCode[LightingStage].Add(DefinesStr + TemplateLight);

    if Node <> nil then
      Shader.EnableEffects(Node.FdEffects, FCode);
  end;

  Result := FCode;
end;

procedure TLightShader.SetUniforms(AProgram: TX3DShaderProgram);
begin
  if LightUniformName1 <> '' then
    AProgram.SetUniform(Format(LightUniformName1, [Number]), LightUniformValue1);
  if LightUniformName2 <> '' then
    AProgram.SetUniform(Format(LightUniformName2, [Number]), LightUniformValue2);
end;

procedure TLightShader.SetDynamicUniforms(AProgram: TX3DShaderProgram);
var
  Color3, AmbientColor3: TVector3;
  Color4, AmbientColor4: TVector4;
  Position: TVector4;
  LiPos: TAbstractPositionalLightNode;
  LiSpot1: TSpotLightNode_1;
  LiSpot: TSpotLightNode;
  LightToEyeSpace: PMatrix4;
begin
  { calculate Color4 = light color * light intensity }
  Color3 := Node.FdColor.Value * Node.FdIntensity.Value;
  Color4 := Vector4(Color3, 1);

  { calculate AmbientColor4 = light color * light ambient intensity }
  if Node.FdAmbientIntensity.Value < 0 then
    AmbientColor4 := Color4 else
  begin
    AmbientColor3 := Node.FdColor.Value * Node.FdAmbientIntensity.Value;
    AmbientColor4 := Vector4(AmbientColor3, 1);
  end;

  if Light^.WorldCoordinates then
    LightToEyeSpace := @RenderingCamera.Matrix
  else
    LightToEyeSpace := @Shader.SceneModelView;

  { This is incorrect, at least on Linux x86_64 and Darwin x86_64
    (works OK on Darwin i386), with FPC 3.0.2.
    Possibly TGenericMatrix4.Multiply has then equal addresses
    for Result and argument, although I didn't manage to "catch it red-handed"
    (it seems that merely adding a check to TGenericMatrix4.Multiply
    about it, disables this optimization, so everything is OK then). }
  // Position := Light^.Position;
  // Position := LightToEyeSpace^ * Position;

  Position := LightToEyeSpace^ * Light^.Position;

  { Note that we cut off last component of Node.Position,
    we don't need it. #defines tell the shader whether we deal with direcional
    or positional light. }
  AProgram.SetUniform(Format('castle_LightSource%dPosition', [Number]),
    Position.XYZ);

  if Node is TAbstractPositionalLightNode then
  begin
    LiPos := TAbstractPositionalLightNode(Node);
    if LiPos is TSpotLightNode_1 then
    begin
      LiSpot1 := TSpotLightNode_1(Node);
      AProgram.SetUniform(Format('castle_LightSource%dSpotCosCutoff', [Number]),
        LiSpot1.SpotCosCutoff);
      AProgram.SetUniform(Format('castle_LightSource%dSpotDirection', [Number]),
        LightToEyeSpace^.MultDirection(Light^.Direction));
      if LiSpot1.SpotExponent <> 0 then
      begin
        AProgram.SetUniform(Format('castle_LightSource%dSpotExponent', [Number]),
          LiSpot1.SpotExponent);
      end;
    end else
    if LiPos is TSpotLightNode then
    begin
      LiSpot := TSpotLightNode(Node);
      AProgram.SetUniform(Format('castle_LightSource%dSpotCosCutoff', [Number]),
        LiSpot.SpotCosCutoff);
      AProgram.SetUniform(Format('castle_LightSource%dSpotDirection', [Number]),
        LightToEyeSpace^.MultDirection(Light^.Direction));
      if LiSpot.FdBeamWidth.Value < LiSpot.FdCutOffAngle.Value then
      begin
        AProgram.SetUniform(Format('castle_LightSource%dSpotCutoff', [Number]),
          LiSpot.FdCutOffAngle.Value);
      end;
    end;

    if LiPos.HasAttenuation then
      AProgram.SetUniform(Format('castle_LightSource%dAttenuation', [Number]),
        LiPos.FdAttenuation.Value);
  end;

  if Node.FdAmbientIntensity.Value <> 0 then
    AProgram.SetUniform(Format('castle_SideLightProduct%dAmbient', [Number]),
      Shader.MaterialAmbient * AmbientColor4);

  if not ( (Shader.MaterialSpecular[0] = 0) and
           (Shader.MaterialSpecular[1] = 0) and
           (Shader.MaterialSpecular[2] = 0)) then
    AProgram.SetUniform(Format('castle_SideLightProduct%dSpecular', [Number]),
      Shader.MaterialSpecular * Color4);

  { depending on COLOR_PER_VERTEX define, only one of these uniforms
    will be actually used. }
  if Shader.MaterialFromColor then
    AProgram.SetUniform(Format('castle_LightSource%dDiffuse', [Number]),
      Color4) else
    AProgram.SetUniform(Format('castle_SideLightProduct%dDiffuse', [Number]),
      Shader.MaterialDiffuse * Color4);
end;

{ TLightShaders -------------------------------------------------------------- }

function TLightShaders.Find(const Node: TAbstractLightNode; out Shader: TLightShader): boolean;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if Items[I].Node = Node then
    begin
      Shader := Items[I];
      Exit(true);
    end;
  Shader := nil;
  Result := false;
end;

{ TX3DShaderProgramBase ------------------------------------------------------ }

procedure TX3DShaderProgramBase.Link;
begin
  inherited;

  UniformCastle_ModelViewMatrix      := Uniform('castle_ModelViewMatrix'     , uaIgnore);
  UniformCastle_ProjectionMatrix     := Uniform('castle_ProjectionMatrix'    , uaIgnore);
  UniformCastle_NormalMatrix         := Uniform('castle_NormalMatrix'        , uaIgnore);
  UniformCastle_MaterialDiffuseAlpha := Uniform('castle_MaterialDiffuseAlpha', uaIgnore);
  UniformCastle_MaterialShininess    := Uniform('castle_MaterialShininess'   , uaIgnore);
  UniformCastle_SceneColor           := Uniform('castle_SceneColor'          , uaIgnore);
  UniformCastle_UnlitColor           := Uniform('castle_UnlitColor'          , uaIgnore);

  AttributeCastle_Vertex         := AttributeOptional('castle_Vertex');
  AttributeCastle_Normal         := AttributeOptional('castle_Normal');
  AttributeCastle_ColorPerVertex := AttributeOptional('castle_ColorPerVertex');
  AttributeCastle_FogCoord       := AttributeOptional('castle_FogCoord');
end;

{ TX3DShaderProgram ------------------------------------------------------- }

constructor TX3DShaderProgram.Create;
begin
  inherited;
  EventsObserved := TX3DEventList.Create(false);
  UniformsTextures := TX3DFieldList.Create(false);
end;

destructor TX3DShaderProgram.Destroy;
var
  I: Integer;
begin
  if EventsObserved <> nil then
  begin
    for I := 0 to EventsObserved.Count - 1 do
      EventsObserved[I].RemoveHandler(@EventReceive);
    FreeAndNil(EventsObserved);
  end;
  FreeAndNil(UniformsTextures);
  inherited;
end;

procedure TX3DShaderProgram.BindNonTextureUniform(
  const FieldOrEvent: TX3DInterfaceDeclaration;
  const EnableDisable: boolean);
var
  UniformField: TX3DField;
  UniformEvent, ObservedEvent: TX3DEvent;
begin
  UniformField := FieldOrEvent.Field;
  UniformEvent := FieldOrEvent.Event;

  { Set initial value for this GLSL uniform variable,
    from VRML field or exposedField }

  if UniformField <> nil then
  try
    { Ok, we have a field with a value (interface declarations with
      fields inside ComposedShader / Effect always have a value).
      So set GLSL uniform variable from this field. }
    SetUniformFromField(UniformField.X3DName, UniformField, EnableDisable);
  except
    { We capture EGLSLUniformInvalid, converting it to WritelnWarning and exit.
      This way we will not add this field to EventsObserved. }
    on E: EGLSLUniformInvalid do
    begin
      WritelnWarning('VRML/X3D', E.Message);
      Exit;
    end;
  end;

  { Allow future changing of this GLSL uniform variable,
    from VRML eventIn or exposedField }

  { calculate ObservedEvent }
  ObservedEvent := nil;
  if (UniformField <> nil) and UniformField.Exposed then
    ObservedEvent := UniformField.ExposedEvents[false] else
  if (UniformEvent <> nil) and UniformEvent.InEvent then
    ObservedEvent := UniformEvent;

  if ObservedEvent <> nil then
  begin
    ObservedEvent.OnReceive.Add(@EventReceive);
    EventsObserved.Add(ObservedEvent);
  end;
end;

procedure TX3DShaderProgram.SetUniformFromField(
  const UniformName: string; const UniformValue: TX3DField;
  const EnableDisable: boolean);
var
  TempF: TSingleList;
  TempVec2f: TVector2List;
  TempVec3f: TVector3List;
  TempVec4f: TVector4List;
  TempMat3f: TMatrix3List;
  TempMat4f: TMatrix4List;
begin
  { program must be active to set uniform values. }
  if EnableDisable then
    Enable;

  if UniformValue is TSFBool then
    SetUniform(UniformName, TSFBool(UniformValue).Value, true) else
  if UniformValue is TSFLong then
    { Handling of SFLong also takes care of SFInt32. }
    SetUniform(UniformName, TSFLong(UniformValue).Value, true) else
  if UniformValue is TSFVec2f then
    SetUniform(UniformName, TSFVec2f(UniformValue).Value, true) else
  { Check TSFColor first, otherwise TSFVec3f would also catch and handle
    TSFColor. And we don't want this: for GLSL, color is passed
    as vec4 (so says the spec, I guess that the reason is that for GLSL most
    input/output colors are vec4). }
  if UniformValue is TSFColor then
    SetUniform(UniformName, Vector4(TSFColor(UniformValue).Value, 1.0), true) else
  if UniformValue is TSFVec3f then
    SetUniform(UniformName, TSFVec3f(UniformValue).Value, true) else
  if UniformValue is TSFVec4f then
    SetUniform(UniformName, TSFVec4f(UniformValue).Value, true) else
  if UniformValue is TSFRotation then
    SetUniform(UniformName, TSFRotation(UniformValue).Value, true) else
  if UniformValue is TSFMatrix3f then
    SetUniform(UniformName, TSFMatrix3f(UniformValue).Value, true) else
  if UniformValue is TSFMatrix4f then
    SetUniform(UniformName, TSFMatrix4f(UniformValue).Value, true) else
  if UniformValue is TSFFloat then
    SetUniform(UniformName, TSFFloat(UniformValue).Value, true) else
  if UniformValue is TSFDouble then
    { SFDouble also takes care of SFTime }
    SetUniform(UniformName, TSFDouble(UniformValue).Value, true) else

  { Double-precision vector and matrix types.

    Note that X3D spec specifies only mapping for SF/MFVec3d, 4d
    (not specifying any mapping for SF/MFVec2d, and all matrix types).
    And it specifies that they map to types float3, float4 ---
    which are not valid types in GLSL?

    So I simply ignore non-sensible specification, and take
    the reasonable approach: support all double-precision vectors and matrices,
    just like single-precision. }
  if UniformValue is TSFVec2d then
    SetUniform(UniformName, Vector2(TSFVec2d(UniformValue).Value), true) else
  if UniformValue is TSFVec3d then
    SetUniform(UniformName, Vector3(TSFVec3d(UniformValue).Value), true) else
  if UniformValue is TSFVec4d then
    SetUniform(UniformName, Vector4(TSFVec4d(UniformValue).Value), true) else
  if UniformValue is TSFMatrix3d then
    SetUniform(UniformName, Matrix3(TSFMatrix3d(UniformValue).Value), true) else
  if UniformValue is TSFMatrix4d then
    SetUniform(UniformName, Matrix4(TSFMatrix4d(UniformValue).Value), true) else

  { Now repeat this for array types }
  if UniformValue is TMFBool then
    SetUniform(UniformName, TMFBool(UniformValue).Items, true) else
  if UniformValue is TMFLong then
    SetUniform(UniformName, TMFLong(UniformValue).Items, true) else
  if UniformValue is TMFVec2f then
    SetUniform(UniformName, TMFVec2f(UniformValue).Items, true) else
  if UniformValue is TMFColor then
  begin
    TempVec4f := TMFColor(UniformValue).Items.ToVector4(1.0);
    try
      SetUniform(UniformName, TempVec4f, true);
    finally FreeAndNil(TempVec4f) end;
  end else
  if UniformValue is TMFVec3f then
    SetUniform(UniformName, TMFVec3f(UniformValue).Items, true) else
  if UniformValue is TMFVec4f then
    SetUniform(UniformName, TMFVec4f(UniformValue).Items, true) else
  if UniformValue is TMFRotation then
    SetUniform(UniformName, TMFRotation(UniformValue).Items, true) else
  if UniformValue is TMFMatrix3f then
    SetUniform(UniformName, TMFMatrix3f(UniformValue).Items, true) else
  if UniformValue is TMFMatrix4f then
    SetUniform(UniformName, TMFMatrix4f(UniformValue).Items, true) else
  if UniformValue is TMFFloat then
    SetUniform(UniformName, TMFFloat(UniformValue).Items, true) else
  if UniformValue is TMFDouble then
  begin
    TempF := TMFDouble(UniformValue).Items.ToSingle;
    try
      SetUniform(UniformName, TempF, true);
    finally FreeAndNil(TempF) end;
  end else
  if UniformValue is TMFVec2d then
  begin
    TempVec2f := TMFVec2d(UniformValue).Items.ToVector2;
    try
      SetUniform(UniformName, TempVec2f, true);
    finally FreeAndNil(TempVec2f) end;
  end else
  if UniformValue is TMFVec3d then
  begin
    TempVec3f := TMFVec3d(UniformValue).Items.ToVector3;
    try
      SetUniform(UniformName, TempVec3f, true);
    finally FreeAndNil(TempVec3f) end;
  end else
  if UniformValue is TMFVec4d then
  begin
    TempVec4f := TMFVec4d(UniformValue).Items.ToVector4;
    try
      SetUniform(UniformName, TempVec4f, true);
    finally FreeAndNil(TempVec4f) end;
  end else
  if UniformValue is TMFMatrix3d then
  begin
    TempMat3f := TMFMatrix3d(UniformValue).Items.ToMatrix3;
    try
      SetUniform(UniformName, TempMat3f, true);
    finally FreeAndNil(TempMat3f) end;
  end else
  if UniformValue is TMFMatrix4d then
  begin
    TempMat4f := TMFMatrix4d(UniformValue).Items.ToMatrix4;
    try
      SetUniform(UniformName, TempMat4f, true);
    finally FreeAndNil(TempMat4f) end;
  end else

  (*
  if (UniformValue is TSFNode) or
     (UniformValue is TMFNode) then
  begin
    { Nothing to do, these will be set by TGLSLRenderer.Enable.
      Right now, these are never passed here. }
  end else
 *)

    { TODO: other field types, full list is in X3D spec in
      "OpenGL shading language (GLSL) binding".
      Remaining:
      SF/MFImage }
    WritelnWarning('VRML/X3D', 'Setting uniform GLSL variable from X3D field type "' + UniformValue.X3DType + '" not supported');

  if EnableDisable then
    { TODO: this should restore previously bound program }
    Disable;
end;

procedure TX3DShaderProgram.EventReceive(
  Event: TX3DEvent; Value: TX3DField; const Time: TX3DTime);
var
  UniformName: string;
  Scene: TX3DEventsEngine;
begin
  if Event.ParentExposedField = nil then
    UniformName := Event.X3DName
  else
    UniformName := Event.ParentExposedField.X3DName;

  try
    SetUniformFromField(UniformName, Value, true);
  except
    { We capture EGLSLUniformInvalid, converting it to WritelnWarning.
      This way we remove this event from OnReceive list. }
    on E: EGLSLUniformInvalid do
    begin
      WritelnWarning('VRML/X3D', E.Message);
      Event.RemoveHandler(@EventReceive);
      EventsObserved.Remove(Event);
      Exit;
    end;
  end;

  { Although ExposedEvents implementation already sends notification
    about changes to Scene, we can also get here
    by eventIn invocation (which doesn't trigger
    Scene.InternalChangedField, since it doesn't change a field...).
    So we should explicitly do VisibleChangeHere here, to make sure
    it gets called when uniform changed. }
  if Event.ParentNode <> nil then
  begin
    Scene := (Event.ParentNode as TX3DNode).Scene;
    if Scene <> nil then
      Scene.VisibleChangeHere([vcVisibleGeometry, vcVisibleNonGeometry]);
  end;
end;

procedure TX3DShaderProgram.BindUniforms(const Node: TX3DNode;
  const EnableDisable: boolean);
var
  I: Integer;
  IDecl: TX3DInterfaceDeclaration;
begin
  Assert(Node.HasInterfaceDeclarations <> []);
  Assert(Node.InterfaceDeclarations <> nil);
  for I := 0 to Node.InterfaceDeclarations.Count - 1 do
  begin
    IDecl := Node.InterfaceDeclarations[I];
    if (IDecl.Field <> nil) and
       ((IDecl.Field is TSFNode) or
        (IDecl.Field is TMFNode)) then
      UniformsTextures.Add(IDecl.Field) else
      BindNonTextureUniform(IDecl, EnableDisable);
  end;
end;

procedure TX3DShaderProgram.BindUniforms(const Nodes: TX3DNodeList;
  const EnableDisable: boolean);
var
  I: Integer;
begin
  for I := 0 to Nodes.Count - 1 do
    BindUniforms(Nodes[I], EnableDisable);
end;

{ TTextureCoordinateShader --------------------------------------------------- }

class function TTextureCoordinateShader.CoordName(const TexUnit: Cardinal): string;
begin
  Result := Format('castle_TexCoord%d', [TexUnit]);
end;

class function TTextureCoordinateShader.MatrixName(const TexUnit: Cardinal): string;
begin
  Result := Format('castle_TextureMatrix%d', [TexUnit]);
end;

procedure TTextureCoordinateShader.Prepare(var Hash: TShaderCodeHash);
var
  IntHash: LongWord;
begin
{$include norqcheckbegin.inc}
  IntHash :=
    1 +
    971 * Ord(HasMatrixTransform);
  Hash.AddInteger(977 * (TextureUnit + 1) * IntHash);
{$include norqcheckend.inc}
end;

procedure TTextureCoordinateShader.Enable(var TextureApply, TextureColorDeclare,
  TextureCoordInitialize, TextureCoordMatrix,
  TextureAttributeDeclare, TextureVaryingDeclare, TextureUniformsDeclare,
  GeometryVertexSet, GeometryVertexZero, GeometryVertexAdd: string);
var
  TexCoordName, TexMatrixName: string;
begin
  TexCoordName := CoordName(TextureUnit);
  TexMatrixName := MatrixName(TextureUnit);

  TextureCoordInitialize += Format('%s = castle_MultiTexCoord%d;' + NL,
    [TexCoordName, TextureUnit]);
  TextureAttributeDeclare += Format('attribute vec4 castle_MultiTexCoord%d;' + NL, [TextureUnit]);
  TextureVaryingDeclare += Format('varying vec4 %s;' + NL, [TexCoordName]);

  if HasMatrixTransform then
    TextureCoordMatrix += Format('%s = %s * %0:s;' + NL,
      [TexCoordName, TexMatrixName]);

  GeometryVertexSet  += Format('%s  = gl_in[index].%0:s;' + NL, [TexCoordName]);
  GeometryVertexZero += Format('%s  = vec4(0.0);' + NL, [TexCoordName]);
  { NVidia will warn here "... might be used before being initialized".
    Which is of course true --- but we depend that author will always call
    geometryVertexZero() before geometryVertexAdd(). }
  GeometryVertexAdd  += Format('%s += gl_in[index].%0:s * scale;' + NL, [TexCoordName]);
end;

{ TTextureShader ------------------------------------------------------------- }

procedure TTextureShader.Prepare(var Hash: TShaderCodeHash);
var
  IntHash: LongWord;
begin
  inherited;

{$include norqcheckbegin.inc}
  IntHash :=
    1 +
    181 * Ord(TextureType) +
    191 * ShadowMapSize +
    193 * Ord(ShadowVisualizeDepth) +
    Env.Hash;
  if ShadowLight <> nil then
    IntHash += PtrUInt(ShadowLight);
  Hash.AddInteger(179 * (TextureUnit + 1) * IntHash);
  { Don't directly add Node to the Hash, it would prevent a lot of sharing.
    Node is only used to get effects. }
  Hash.AddEffects(Node.FdEffects.Items);
{$include norqcheckend.inc}
end;

class function TTextureShader.TextureEnvMix(const AEnv: TTextureEnv;
  const FragmentColor, CurrentTexture: string;
  const ATextureUnit: Cardinal): string;
var
  { GLSL code to get Arg2 (what is coming from MultiTexture.source) }
  Arg2: string;
begin
  if AEnv.Disabled then Exit('');

  // if AEnv.Source[cRGB] = csConstant then
  //   { TODO: Fix new shader pipeline without deprecated gl_xxx usage:
  //     We need to pass MultiTexture.color/factor as special
  //     uniform, instead of using (per-unit) gl_TextureEnvColor.
  //     Account for MultiTexture.color/factor inside TTextureEnv.Hash. }
  //   Arg2 := Format('castle_TextureEnvColor%d', [ATextureUnit]);
  //   Arg2 := 'castle_TextureEnvColor'; // maybe this is enough?
  // else

  { assume AEnv.Source[cRGB] = csPreviousTexture }
  Arg2 := FragmentColor;

  case AEnv.Combine[cRGB] of
    coReplace:
      begin
        if AEnv.SourceArgument[cRGB] = ta0 then
          { mode is SELECTARG2 }
          Result := FragmentColor + ' = ' + Arg2 + ';' else
          { assume CurrentTextureArgument = ta0, mode = REPLACE or SELECTARG1 }
          Result := FragmentColor + ' = ' + CurrentTexture + ';';
      end;
    coAdd:
      begin
        if FragmentColor = Arg2 then
          Result := FragmentColor + ' += ' + CurrentTexture + ';' else
          Result := FragmentColor + ' = ' + CurrentTexture + ' + ' + Arg2 + ';';
      end;
    coSubtract:
      Result := FragmentColor + ' = ' + CurrentTexture + ' - ' + Arg2 + ';';
    else
      begin
        { assume coModulate }
        if FragmentColor = Arg2 then
          Result := FragmentColor + ' *= ' + CurrentTexture + ';' else
          Result := FragmentColor + ' = ' + CurrentTexture + ' * ' + Arg2 + ';';
      end;
  end;

  case AEnv.TextureFunction of
    tfComplement    : Result += FragmentColor + '.rgb = vec3(1.0) - ' + FragmentColor + '.rgb;';
    tfAlphaReplicate: Result += FragmentColor + '.rgb = vec3(' + FragmentColor + '.a);';
  end;

  { TODO: this handles only a subset of possible values:
    - different combine values on RGB/alpha not handled yet.
      We just check Env.Combine[cRGB], and assume it's equal Env.Combine[cAlpha].
      Same for Env.Source: we assume Env.Source[cRGB] equal to Env.Source[cAlpha].
    - Scale is ignored (assumed 1)
    - CurrentTextureArgument, SourceArgument ignored (assumed ta0, ta1),
      except for GL_REPLACE case
    - many Combine values ignored (treated like modulate),
      and so also NeedsConstantColor and InterpolateAlphaSource are ignored.
  }
end;

procedure TTextureShader.Enable(var TextureApply, TextureColorDeclare,
  TextureCoordInitialize, TextureCoordMatrix,
  TextureAttributeDeclare, TextureVaryingDeclare, TextureUniformsDeclare,
  GeometryVertexSet, GeometryVertexZero, GeometryVertexAdd: string);
const
  SamplerFromTextureType: array [TTextureType] of string =
  ('sampler2D', 'sampler2DShadow', 'samplerCube', 'sampler3D', '');
var
  TextureSampleCall, TexCoordName: string;
  ShadowLightShader: TLightShader;
  Code: TShaderSource;
  SamplerType: string;
begin
  inherited;

  if TextureType <> ttShader then
  begin
    UniformName := Format('castle_texture_%d', [TextureUnit]);
    UniformValue := TextureUnit;
  end else
    UniformName := '';

  TexCoordName := CoordName(TextureUnit);

  if (TextureType = tt2DShadow) and
      ShadowVisualizeDepth then
  begin
    { visualizing depth map requires a little different approach:
      - we use shadow_depth() instead of shadow() function
      - we *set* gl_FragColor, not modulate it, to ignore previous textures
      - we call "return" after, to ignore following textures
      - the sampler is sampler2D, not sampler2DShadow
      - also, we use gl_FragColor (while we should use fragment_color otherwise),
        because we don't care about previous texture operations and
        we want to return immediately. }
    TextureSampleCall := 'vec4(vec3(shadow_depth(%s, %s)), gl_FragColor.a)';
    TextureApply += Format('gl_FragColor = ' + TextureSampleCall + ';' + NL +
      'return;',
      [UniformName, TexCoordName]);
    TextureUniformsDeclare += Format('uniform sampler2D %s;' + NL,
      [UniformName]);
  end else
  begin
    SamplerType := SamplerFromTextureType[TextureType];
    { For variance shadow maps, use normal sampler2D, not sampler2DShadow }
    if (Shader.ShadowSampling = ssVarianceShadowMaps) and
       (TextureType = tt2DShadow) then
      SamplerType := 'sampler2D';

    if (TextureType = tt2DShadow) and
       (ShadowLight <> nil) and
       Shader.LightShaders.Find(ShadowLight, ShadowLightShader) then
    begin
      Shader.Plug(stFragment, Format(
        'uniform %s %s;' +NL+
        'varying vec4 %s;' +NL+
        '%s' +NL+
        'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir)' +NL+
        '{' +NL+
        '  scale *= shadow(%s, castle_TexCoord%d, %d.0);' +NL+
        '}',
        [SamplerType, UniformName,
         TexCoordName,
         Shader.DeclareShadowFunctions,
         UniformName, TextureUnit, ShadowMapSize]),
        ShadowLightShader.Code);
    end else
    begin
      if TextureColorDeclare = '' then
        TextureColorDeclare := 'vec4 texture_color;' + NL;
      case TextureType of
        tt2D:
          { texture2DProj reasoning:
            Most of the time, 'texture2D(%s, %s.st)' would be enough.
            But we may get 4D tex coords (that is, with last component <> 1)
            - through TextureCoordinate4D
            - through projected texture mapping, when using perspective light
              (spot light) or perspective viewpoint.

            TextureUnit = 0 check reasoning:
            Even when HAS_TEXTURE_COORD_SHIFT is defined (PLUG_texture_coord_shift
            was used), use it only for 0th texture unit. Parallax bump mapping
            calculates the shift, assuming that transformations to tangent space
            follow 0th texture coordinates. Also, for parallax bump mapping,
            we have to assume the 0th texture has simple 2D coords (not 4D). }
          if TextureUnit = 0 then
            TextureSampleCall := NL+
              '#ifdef HAS_TEXTURE_COORD_SHIFT' +NL+
              '  texture2D(%0:s, texture_coord_shifted(%1:s.st))' +NL+
              '#else' +NL+
              '  texture2DProj(%0:s, %1:s)' +NL+
              '#endif' + NL else
            TextureSampleCall := 'texture2DProj(%0:s, %1:s)';
        tt2DShadow: TextureSampleCall := 'vec4(vec3(shadow(%s, %s, ' +IntToStr(ShadowMapSize) + '.0)), fragment_color.a)';
        ttCubeMap : TextureSampleCall := 'textureCube(%s, %s.xyz)';
        { For 3D textures, remember we may get 4D tex coords
          through TextureCoordinate4D, so we have to use texture3DProj }
        tt3D      : TextureSampleCall := 'texture3DProj(%s, %s)';
        ttShader  : TextureSampleCall := 'vec4(1.0, 0.0, 1.0, 1.0)';
        else raise EInternalError.Create('TShader.EnableTexture:TextureType?');
      end;

      Code := TShaderSource.Create;
      try
        if TextureType <> ttShader then
          Code[stFragment].Add(Format(
            'texture_color = ' + TextureSampleCall + ';' +NL+
            '/* PLUG: texture_color (texture_color, %0:s, %1:s) */' +NL,
            [UniformName, TexCoordName])) else
          Code[stFragment].Add(Format(
            'texture_color = ' + TextureSampleCall + ';' +NL+
            '/* PLUG: texture_color (texture_color, %0:s) */' +NL,
            [TexCoordName]));

        Shader.EnableEffects(Node.FdEffects, Code, true);

        { Add generated Code to Shader.Source. Code[stFragment][0] for texture
          is a little special, we add it to TextureApply that
          will be directly placed within the source. }
        TextureApply += Code[stFragment][0];
        Shader.Source.Append(Code, stFragment);
      finally FreeAndNil(Code) end;

      TextureApply += TextureEnvMix(Env, 'fragment_color', 'texture_color', TextureUnit) + NL;

      if TextureType <> ttShader then
        TextureUniformsDeclare += Format('uniform %s %s;' + NL,
          [SamplerType, UniformName]);
    end;
  end;
end;

{ TDynamicUniformSingle ------------------------------------------------------ }

procedure TDynamicUniformSingle.SetUniform(AProgram: TX3DShaderProgram);
begin
  AProgram.SetUniform(Name, Value);
end;

{ TDynamicUniformVec3 -------------------------------------------------------- }

procedure TDynamicUniformVec3.SetUniform(AProgram: TX3DShaderProgram);
begin
  AProgram.SetUniform(Name, Value);
end;

{ TDynamicUniformVec4 -------------------------------------------------------- }

procedure TDynamicUniformVec4.SetUniform(AProgram: TX3DShaderProgram);
begin
  AProgram.SetUniform(Name, Value);
end;

{ TDynamicUniformMat4 -------------------------------------------------------- }

procedure TDynamicUniformMat4.SetUniform(AProgram: TX3DShaderProgram);
begin
  AProgram.SetUniform(Name, Value);
end;

{ TSurfaceTextureShader ------------------------------------------------------ }

class function TSurfaceTextureShader.UniformTextureName(const SurfaceTexture: TSurfaceTexture): string; static;
const
  Names: array [TSurfaceTexture] of string = (
    'castle_ambientTexture',
    'castle_specularTexture',
    'castle_shininessTexture'
  );
begin
  Result := Names[SurfaceTexture];
end;

{ TShader ---------------------------------------------------------------- }

function InsertIntoString(const Base: string; const P: Integer; const S: string): string;
begin
  Result := Copy(Base, 1, P - 1) + S + SEnding(Base, P);
end;

const
  DefaultVertexShader   : array [ { phong shading } boolean ] of string =
  ( {$I template_gouraud.vs.inc}, {$I template_phong.vs.inc} );
  DefaultFragmentShader : array [ { phong shading } boolean ] of string =
  ( {$I template_gouraud.fs.inc}, {$I template_phong.fs.inc} );
  DefaultGeometryShader = {$I template.gs.inc};

  // TODO: fix this to pass color in new shaders (not using deprecated gl_FrontColor, gl_BackColor)
  (*
  GeometryShaderPassColors =
    '#version 150 compatibility' +NL+

    'void PLUG_geometry_vertex_set(const int index)' +NL+
    '{' +NL+
    '  gl_FrontColor = gl_in[index].gl_FrontColor;' +NL+
    '  gl_BackColor  = gl_in[index].gl_BackColor;' +NL+
    '}' +NL+

    'void PLUG_geometry_vertex_zero()' +NL+
    '{' +NL+
    '  gl_FrontColor = vec4(0.0);' +NL+
    '  gl_BackColor  = vec4(0.0);' +NL+
    '}' +NL+

    'void PLUG_geometry_vertex_add(const int index, const float scale)' +NL+
    '{' +NL+
    '  gl_FrontColor += gl_in[index].gl_FrontColor * scale;' +NL+
    '  gl_BackColor  += gl_in[index].gl_BackColor  * scale;' +NL+
    '}' +NL;
  *)

constructor TShader.Create;
begin
  inherited;
  Source := TShaderSource.Create;
  LightShaders := TLightShaders.Create;
  TextureShaders := TTextureCoordinateShaderList.Create;
  UniformsNodes := TX3DNodeList.Create(false);
  DynamicUniforms := TDynamicUniformList.Create(true);
  TextureMatrix := TCardinalList.Create;

  WarnMissingPlugs := true;
end;

destructor TShader.Destroy;
begin
  FreeAndNil(UniformsNodes);
  FreeAndNil(LightShaders);
  FreeAndNil(TextureShaders);
  FreeAndNil(Source);
  FreeAndNil(DynamicUniforms);
  FreeAndNil(TextureMatrix);
  inherited;
end;

procedure TShader.Clear;
var
  SurfaceTexture: TSurfaceTexture;
  ShaderType: TShaderType;
begin
  for ShaderType in TShaderType do
    Source[ShaderType].Clear;

  WarnMissingPlugs := true;
  HasGeometryMain := false;

  { the rest of fields just restored to default clear state }
  UniformsNodes.Clear;
  TextureCoordGen := '';
  ClipPlane := '';
  FragmentEnd := '';
  FShadowSampling := Low(TShadowSampling);
  PlugIdentifiers := 0;
  LightShaders.Count := 0;
  TextureShaders.Count := 0;
  FCodeHash.Clear;
  CodeHashFinalized := false;
  SelectedNode := nil;
  FShapeRequiresShaders := false;
  FBumpMapping := Low(TBumpMapping);
  FNormalMapTextureUnit := 0;
  FNormalMapTextureCoordinatesId := 0;
  FHeightMapInAlpha := false;
  FHeightMapScale := 0;
  for SurfaceTexture in TSurfaceTexture do
    { No need to reset other FSurfaceTextureShaders[SurfaceTexture] properties. }
    FSurfaceTextureShaders[SurfaceTexture].Enable := false;
  FFogEnabled := false;
  { No need to reset, will be set when FFogEnabled := true
  FFogType := Low(TFogType);
  FFogCoordinateSource := Low(TFogCoordinateSource); }
  AppearanceEffects := nil;
  GroupEffects := nil;
  Lighting := false;
  MaterialFromColor := false;
  FPhongShading := false;
  ShapeBoundingBox := TBox3D.Empty;
  MaterialAmbient := TVector4.Zero;
  MaterialDiffuse := TVector4.Zero;
  MaterialSpecular := TVector4.Zero;
  MaterialEmission := TVector4.Zero;
  MaterialShininessExp := 0;
  MaterialUnlit := TVector4.Zero;
  DynamicUniforms.Clear;
  TextureMatrix.Clear;
  NeedsCameraInverseMatrix := false;
end;

procedure TShader.Initialize(const APhongShading: boolean);
begin
  FPhongShading := APhongShading;
  FCodeHash.AddInteger(Ord(PhongShading) * 877);

  Source[stVertex].Count := 1;
  Source[stVertex][0] := DefaultVertexShader[PhongShading];
  Source[stFragment].Count := 1;
  Source[stFragment][0] := DefaultFragmentShader[PhongShading];
  Source[stGeometry].Count := 1;
  Source[stGeometry][0] := DefaultGeometryShader;
end;

procedure TShader.Plug(const EffectPartType: TShaderType; PlugValue: string;
  CompleteCode: TShaderSource; const ForwardDeclareInFinalShader: boolean);
const
  PlugPrefix = 'PLUG_';

  { Find PLUG_xxx function inside PlugValue.
    Returns xxx (the part after PLUG_),
    and DeclaredParameters (or this plug function). Or '' if not found. }
  function FindPlugName(const PlugValue: string;
    out DeclaredParameters: string): string;
  const
    IdentifierChars = ['0'..'9', 'a'..'z', 'A'..'Z', '_'];
  var
    P, PBegin, DPBegin, DPEnd, SearchStart: Integer;
  begin
    SearchStart := 1;
    repeat
      P := PosEx(PlugPrefix, PlugValue, SearchStart);
      if P = 0 then Exit('');

      { if code below will decide that it's an incorrect PLUG_ definition,
        it will do Continue, and we will search again from the next position. }
      SearchStart := P + Length(PlugPrefix);

      { There must be whitespace before PLUG_ }
      if (P > 1) and (not (PlugValue[P - 1] in WhiteSpaces)) then Continue;
      P += Length(PlugPrefix);
      PBegin := P;
      { There must be at least one identifier char after PLUG_ }
      if (P > Length(PlugValue)) or
         (not (PlugValue[P] in IdentifierChars)) then Continue;
      repeat
        Inc(P);
      until (P > Length(PlugValue)) or (not (PlugValue[P] in IdentifierChars));
      { There must be a whitespace or ( after PLUG_xxx }
      if (P > Length(PlugValue)) or (not (PlugValue[P] in (WhiteSpaces + ['(']))) then
        Continue;

      Result := CopyPos(PlugValue, PBegin, P - 1);

      DPBegin := P - 1;
      if not MoveToOpeningParen(PlugValue, DPBegin) then Continue;
      DPEnd := DPBegin;
      if not MoveToMatchingParen(PlugValue, DPEnd) then Continue;

      DeclaredParameters := CopyPos(PlugValue, DPBegin, DPEnd);
      { if you managed to get here, then we have correct Result and DeclaredParameters }
      Exit;
    until false;
  end;

  function FindPlugOccurrence(const CommentBegin, Code: string;
    const CodeSearchBegin: Integer; out PBegin, PEnd: Integer): boolean;
  begin
    Result := false;
    PBegin := PosEx(CommentBegin, Code, CodeSearchBegin);
    if PBegin <> 0 then
    begin
      PEnd := PosEx('*/', Code, PBegin + Length(CommentBegin));
      Result :=  PEnd <> 0;
      if not Result then
        WritelnWarning('VRML/X3D', Format('Plug comment "%s" not properly closed, treating like not declared',
          [CommentBegin]));
    end;
  end;

  procedure InsertIntoCode(Code: TCastleStringList;
    const CodeIndex, P: Integer; const S: string);
  begin
    Code[CodeIndex] := InsertIntoString(Code[CodeIndex], P, S);
  end;

var
  PlugName, ProcedureName, PlugForwardDeclaration: string;

  function LookForPlugDeclaration(CodeForPlugDeclaration: TCastleStringList): boolean;
  var
    AnyOccurrencesInThisCodeIndex: boolean;
    PBegin, PEnd, CodeSearchBegin, CodeIndex: Integer;
    CommentBegin, Parameter: string;
  begin
    CommentBegin := '/* PLUG: ' + PlugName + ' ';
    Result := false;
    for CodeIndex := 0 to CodeForPlugDeclaration.Count - 1 do
    begin
      CodeSearchBegin := 1;
      AnyOccurrencesInThisCodeIndex := false;
      while FindPlugOccurrence(CommentBegin, CodeForPlugDeclaration[CodeIndex],
        CodeSearchBegin, PBegin, PEnd) do
      begin
        Parameter := Trim(CopyPos(CodeForPlugDeclaration[CodeIndex], PBegin + Length(CommentBegin), PEnd - 1));
        InsertIntoCode(CodeForPlugDeclaration, CodeIndex, PBegin, ProcedureName + Parameter + ';' + NL);

        { do not find again the same plug comment by FindPlugOccurrence }
        CodeSearchBegin := PEnd;

        AnyOccurrencesInThisCodeIndex := true;
        Result := true;
      end;

      if AnyOccurrencesInThisCodeIndex then
      begin
        { added "plugged_x" function must be forward declared first.
          Otherwise it could be defined after it is needed, or inside different
          compilation unit. }
        if ForwardDeclareInFinalShader and (CodeIndex = 0) then
          PlugDirectly(Source[EffectPartType], CodeIndex, '/* PLUG-DECLARATIONS */', PlugForwardDeclaration, true) else
          PlugDirectly(CodeForPlugDeclaration, CodeIndex, '/* PLUG-DECLARATIONS */', PlugForwardDeclaration, true);
      end;
    end;
  end;

var
  Code: TCastleStringList;
  PlugDeclaredParameters: string;
  AnyOccurrences: boolean;
begin
  if CompleteCode = nil then
    CompleteCode := Source;
  Code := CompleteCode[EffectPartType];

  { if the final shader code is empty (on this type) then don't insert anything
    (avoid creating shader without main()).

    For geometry shaders (EffectPartType = stGeometry),
    this check actually does nothing. Geometry shaders always have at least
    our code defining geometry_xxx functions, so they are never empty. }
  if Source[EffectPartType].Count = 0 then
    Exit;

  HasGeometryMain := HasGeometryMain or
    ( (EffectPartType = stGeometry) and (Pos('main()', PlugValue) <> 0) );

  repeat
    PlugName := FindPlugName(PlugValue, PlugDeclaredParameters);
    if PlugName = '' then Break;

    { When using some special plugs, we need to do define some symbols. }
    if PlugName = 'texture_coord_shift' then
      PlugDirectly(Source[stFragment], 0, '/* PLUG-DECLARATIONS */',
        '#define HAS_TEXTURE_COORD_SHIFT', false);

    ProcedureName := 'plugged_' + IntToStr(PlugIdentifiers);
    StringReplaceAllVar(PlugValue, 'PLUG_' + PlugName, ProcedureName, false);
    Inc(PlugIdentifiers);

    PlugForwardDeclaration := 'void ' + ProcedureName + PlugDeclaredParameters + ';' + NL;

    AnyOccurrences := LookForPlugDeclaration(Code);
    { If the plug declaration not found in Code, then try to find it in
      the final shader. This happens if your Code is special for given
      light/texture effect, and you try to use a plug that
      is not special to the light/texture effect. For example,
      using PLUG_vertex_object_space inside a X3DTextureNode.effects. }
    if (not AnyOccurrences) and
       (Code <> Source[EffectPartType]) then
      AnyOccurrences := LookForPlugDeclaration(Source[EffectPartType]);

    if (not AnyOccurrences) and WarnMissingPlugs then
      WritelnWarning('VRML/X3D', Format('Plug name "%s" not declared (in shader type "%s")',
        [PlugName, ShaderTypeName[EffectPartType]]));
  until false;

  { regardless if any (and how many) plug points were found,
    always insert PlugValue into Code }
  Code.Add(PlugValue);
end;

function TShader.PlugDirectly(Code: TCastleStringList;
  const CodeIndex: Cardinal;
  const PlugName, PlugValue: string;
  const InsertAtBeginIfNotFound: boolean): boolean;
var
  P: Integer;
begin
  Result := false;

  if CodeIndex < Code.Count then
  begin
    P := Pos(PlugName, Code[CodeIndex]);
    if P <> 0 then
    begin
      Code[CodeIndex] := InsertIntoString(Code[CodeIndex], P, PlugValue + NL);
      Result := true;
    end else
    if InsertAtBeginIfNotFound then
    begin
      Code[CodeIndex] := PlugValue + NL + Code[CodeIndex];
      Result := true;
    end;
  end;

  if (not Result) and WarnMissingPlugs then
    WritelnWarning('VRML/X3D', Format('Plug point "%s" not found', [PlugName]));
end;

procedure TShader.Define(const DefineName: string; const ShaderType: TShaderType);
var
  Declaration: string;
  Code: TCastleStringList;
  {$ifndef OpenGLES}
  I: Integer;
  {$endif}
begin
  Declaration := '#define ' + DefineName;
  Code := Source[ShaderType];

  {$ifdef OpenGLES}
  { Do not add it to all Source[stXxx], as then GLSL compiler
    will say "COLOR_PER_VERTEX macro redefinition",
    because we glue all parts for OpenGLES. }
  if Code.Count > 0 then
    PlugDirectly(Code, 0, '/* PLUG-DECLARATIONS */', Declaration, true);
  {$else}
  for I := 0 to Code.Count - 1 do
    PlugDirectly(Code, I, '/* PLUG-DECLARATIONS */', Declaration, true);
  {$endif}
end;

procedure TShader.EnableEffects(Effects: TMFNode;
  const Code: TShaderSource;
  const ForwardDeclareInFinalShader: boolean);
begin
  EnableEffects(Effects.Items, Code, ForwardDeclareInFinalShader);
end;

procedure TShader.EnableEffects(Effects: TX3DNodeList;
  const Code: TShaderSource;
  const ForwardDeclareInFinalShader: boolean);

  procedure EnableEffect(Effect: TEffectNode);

    procedure EnableEffectPart(Part: TEffectPartNode);
    var
      Contents: string;
    begin
      Contents := Part.Contents;
      if Contents <> '' then
      begin
        Plug(Part.ShaderType, Contents, Code, ForwardDeclareInFinalShader);
        { Right now, for speed, we do not call EnableEffects, or even Plug,
          before LinkProgram. At which point ShapeRequiresShaders
          is already known true. }
        Assert(ShapeRequiresShaders);
      end;
    end;

  var
    I: Integer;
  begin
    if not Effect.FdEnabled.Value then Exit;

    if not (Effect.Language in [slDefault, slGLSL]) then
    begin
      WritelnWarning('VRML/X3D', Format('Unknown shading language "%s" for Effect node',
        [Effect.FdLanguage.Value]));
      Exit;
    end;

    for I := 0 to Effect.FdParts.Count - 1 do
      if Effect.FdParts[I] is TEffectPartNode then
        EnableEffectPart(TEffectPartNode(Effect.FdParts[I]));

    UniformsNodes.Add(Effect);
  end;

var
  I: Integer;
begin
  for I := 0 to Effects.Count - 1 do
    if Effects[I] is TEffectNode then
      EnableEffect(TEffectNode(Effects[I]));
end;

procedure TShader.LinkProgram(AProgram: TX3DShaderProgram;
  const ShapeNiceName: string);
var
  TextureApply, TextureColorDeclare, TextureCoordInitialize, TextureCoordMatrix,
    TextureAttributeDeclare, TextureVaryingDeclare, TextureUniformsDeclare,
    GeometryVertexSet, GeometryVertexZero, GeometryVertexAdd: string;
  TextureUniformsSet: boolean;

  procedure RequireTextureCoordinateForSurfaceTextures;

    { Make sure TextureShaders has an item
      with TextureUnit = given TextureCoordinateId. }
    procedure RequireTextureCoordinateId(const TextureCoordinateId: Cardinal);
    var
      I: Integer;
      TexCoordShader: TTextureCoordinateShader;
    begin
      for I := 0 to TextureShaders.Count - 1 do
        if TextureShaders[I].TextureUnit = TextureCoordinateId then
          Exit;

      { item with necessary TextureUnit not found, so create it }
      TexCoordShader := TTextureCoordinateShader.Create;
      TexCoordShader.HasMatrixTransform := TextureMatrix.IndexOf(TextureCoordinateId) <> -1;
      TexCoordShader.TextureUnit := TextureCoordinateId;
      TextureShaders.Add(TexCoordShader);

      { Note that we don't call

          TexCoordShader.Prepare(FCodeHash);

        to change the hash at this point. It is not needed (the fact that
        we use bump mapping or some "surface texture" was already
        recorded in the hash), and changing hash at this point
        could have bad consequences. }
    end;

  var
    SurfaceTexture: TSurfaceTexture;
  begin
    if FBumpMapping <> bmNone then
      RequireTextureCoordinateId(FNormalMapTextureCoordinatesId);

    for SurfaceTexture in TSurfaceTexture do
      if FSurfaceTextureShaders[SurfaceTexture].Enable then
        RequireTextureCoordinateId(
          FSurfaceTextureShaders[SurfaceTexture].TextureCoordinatesId);
  end;

  procedure EnableTextures;
  var
    I: Integer;
  begin
    TextureApply := '';
    TextureColorDeclare := '';
    TextureCoordInitialize := '';
    TextureCoordMatrix := '';
    TextureAttributeDeclare := '';
    TextureVaryingDeclare := '';
    TextureUniformsDeclare := '';
    GeometryVertexSet := '';
    GeometryVertexZero := '';
    GeometryVertexAdd := '';
    TextureUniformsSet := true;

    for I := 0 to TextureShaders.Count - 1 do
      TextureShaders[I].Enable(TextureApply, TextureColorDeclare,
        TextureCoordInitialize, TextureCoordMatrix,
        TextureAttributeDeclare, TextureVaryingDeclare, TextureUniformsDeclare,
        GeometryVertexSet, GeometryVertexZero, GeometryVertexAdd);
  end;

  { Applies effects from various strings here.
    This also finalizes applying textures. }
  procedure EnableInternalEffects;
  {$ifndef OpenGLES}
  const
    ShadowMapsFunctions: array [TShadowSampling] of string =
    (                               {$I shadow_map_common.fs.inc},
     '#define PCF4'          + NL + {$I shadow_map_common.fs.inc},
     '#define PCF4_BILINEAR' + NL + {$I shadow_map_common.fs.inc},
     '#define PCF16'         + NL + {$I shadow_map_common.fs.inc},
     {$I variance_shadow_map_common.fs.inc});
  {$endif}
  var
    UniformsDeclare: string;
    I: Integer;
  begin
    PlugDirectly(Source[stVertex], 0, '/* PLUG: vertex_eye_space',
      TextureCoordInitialize + TextureCoordGen + TextureCoordMatrix + ClipPlane, false);
    PlugDirectly(Source[stFragment], 0, '/* PLUG: texture_apply',
      TextureColorDeclare + TextureApply, false);
    PlugDirectly(Source[stFragment], 0, '/* PLUG: fragment_end', FragmentEnd, false);

    PlugDirectly(Source[stGeometry], 0, '/* PLUG: geometry_vertex_set' , GeometryVertexSet , false);
    PlugDirectly(Source[stGeometry], 0, '/* PLUG: geometry_vertex_zero', GeometryVertexZero, false);
    PlugDirectly(Source[stGeometry], 0, '/* PLUG: geometry_vertex_add' , GeometryVertexAdd , false);

    UniformsDeclare := '';
    for I := 0 to DynamicUniforms.Count - 1 do
      UniformsDeclare += DynamicUniforms[I].Declaration;
    if NeedsCameraInverseMatrix then
      UniformsDeclare += 'uniform mat4 castle_CameraInverseMatrix;' + NL;

    if not (
      PlugDirectly(Source[stFragment], 0, '/* PLUG-DECLARATIONS */',
        TextureVaryingDeclare + NL + TextureUniformsDeclare
        {$ifndef OpenGLES} + NL + DeclareShadowFunctions {$endif}, false) and
      PlugDirectly(Source[stVertex], 0, '/* PLUG-DECLARATIONS */',
        UniformsDeclare +
        TextureAttributeDeclare + NL + TextureVaryingDeclare, false) ) then
    begin
      { When we cannot find /* PLUG-DECLARATIONS */, it also means we have
        base shader from ComposedShader. In this case, forcing
        TextureXxxDeclare at the beginning of shader code
        (by InsertAtBeginIfNotFound) would be bad (in case ComposedShader
        has some #version at the beginning). So we choose the safer route
        to *not* integrate our texture handling with ComposedShader.

        We also remove uniform values for textures, to avoid
        "unused castle_texture_%d" warning. Setting TextureUniformsSet
        will make it happen. }
      TextureUniformsSet := false;
    end;

    { Don't add to empty Source[stFragment], in case ComposedShader
      doesn't want any fragment shader.
      Only add if we're not using shaders from custom ComposedShader
      (SelectedNode not set). }
    {$ifndef OpenGLES}
    if (Source[stFragment].Count <> 0) and
       (SelectedNode = nil) then
      Source[stFragment].Add(ShadowMapsFunctions[ShadowSampling]);
    {$endif}
  end;

var
  PassLightsUniforms: boolean;

  procedure EnableLights;
  var
    LightShader: TLightShader;
    LightingStage: TShaderType;
  begin
    PassLightsUniforms := false;

    { If we have no fragment/vertex shader (means that we used ComposedShader
      node without one shader) then don't add any code.
      Otherwise we would create a shader without any main() inside.

      Source.Append later also has some safeguard against this,
      but we need to check it earlier (to avoid plugging LightShaderBack),
      and check them both (as vertex and fragment code cooperates,
      so we need both or none).

      Also don't add anything in case we're rendering a custom ComposedShader node. }
    if (Source[stFragment].Count = 0) or
       (Source[stVertex].Count = 0) or
       (SelectedNode <> nil) then
      Exit;

    if Lighting then
    begin
      Source[stFragment][0] := '#define LIT' + NL + Source[stFragment][0];
      Source[stVertex  ][0] := '#define LIT' + NL + Source[stVertex  ][0];

      PassLightsUniforms := true;

      if PhongShading then
        LightingStage := stFragment
      else
        LightingStage := stVertex;

      for LightShader in LightShaders do
      begin
        Plug(LightingStage, LightShader.Code[LightingStage][0]);
        { Append the rest of LightShader, it may contain shadow maps utilities
          and light plugs. }
        Source.Append(LightShader.Code, LightingStage);
      end;
    end else
    begin
      // TODO: fix this to pass color in new shaders (not using deprecated gl_FrontColor, gl_BackColor)
      // Plug(stGeometry, GeometryShaderPassColors);
    end;
  end;

var
  BumpMappingUniformName1: string;
  BumpMappingUniformValue1: LongInt;
  BumpMappingUniformName2: string;
  BumpMappingUniformValue2: Single;

  procedure EnableShaderBumpMapping;
  const
    SteepParallaxDeclarations: array [boolean] of string = ('',
      'float castle_bm_height;' +NL+
      'vec2 castle_parallax_tex_coord;' +NL
    );

    SteepParallaxShift: array [boolean] of string = (
      { Classic parallax bump mapping }
      'float height = (texture2D(castle_normal_map, tex_coord).a - 1.0/2.0) * castle_parallax_bm_scale;' +NL+
      'tex_coord += height * v_to_eye.xy /* / v_to_eye.z*/;' +NL,

      { Steep parallax bump mapping }
      '/* At smaller view angles, much more iterations needed, otherwise ugly' +NL+
      '   aliasing artifacts quickly appear. */' +NL+
      'float num_steps = mix(30.0, 10.0, v_to_eye.z);' +NL+
      'float step = 1.0 / num_steps;' +NL+

      { Should we remove "v_to_eye.z" below, i.e. should we apply
        "offset limiting" ? In works about steep parallax mapping,
        v_to_eye.z is present, and in sample steep parallax mapping
        shader they suggest that it doesn't really matter.
        My tests confirm this, so I leave v_to_eye.z component. }

      'vec2 delta = -v_to_eye.xy * castle_parallax_bm_scale / (v_to_eye.z * num_steps);' +NL+
      'float height = 1.0;' +NL+
      'castle_bm_height = texture2D(castle_normal_map, tex_coord).a;' +NL+

      { TODO: NVidia GeForce FX 5200 fails here with

           error C5011: profile does not support "while" statements
           and "while" could not be unrolled.

        I could workaround this problem (by using
          for (int i = 0; i < steep_steps_max; i++)
        loop and
          if (! (castle_bm_height < height)) break;
        , this is possible to unroll). But it turns out that this still
        (even with steep_steps_max = 1) works much too slow on this hardware...
      }

      'while (castle_bm_height < height)' +NL+
      '{' +NL+
      '  height -= step;' +NL+
      '  tex_coord += delta;' +NL+
      '  castle_bm_height = texture2D(castle_normal_map, tex_coord).a;' +NL+
      '}' +NL+

      { Save for SteepParallaxShadowing }
      'castle_parallax_tex_coord = tex_coord;'
    );

    SteepParallaxShadowing =
      'uniform float castle_parallax_bm_scale;' +NL+
      'uniform sampler2D castle_normal_map;' +NL+
      'varying vec3 castle_light_direction_tangent_space;' +NL+

      'float castle_bm_height;' +NL+
      'vec2 castle_parallax_tex_coord;' +NL+

      { This has to be done after PLUG_texture_coord_shift (done from PLUG_texture_apply),
        as we depend that global castle_bm_height/castle_parallax_tex_coord
        are already set correctly. }
      'void PLUG_steep_parallax_shadow_apply(inout vec4 fragment_color)' +NL+
      '{' +NL+
      '  vec3 light_dir = normalize(castle_light_direction_tangent_space);' +NL+

      '  /* We basically do the same thing as when we calculate tex_coord' +NL+
      '     with steep parallax mapping.' +NL+
      '     Only now we increment height, and we use light_dir instead of' +NL+
      '     v_to_eye. */' +NL+
      '  float num_steps = mix(30.0, 10.0, light_dir.z);' +NL+

      '  float step = 1.0 / num_steps;' +NL+

      '  vec2 delta = light_dir.xy * castle_parallax_bm_scale / (light_dir.z * num_steps);' +NL+

      '  /* Do the 1st step always, otherwise initial height = shadow_map_height' +NL+
      '     and we would be considered in our own shadow. */' +NL+
      '  float height = castle_bm_height + step;' +NL+
      '  vec2 shadow_texture_coord = castle_parallax_tex_coord + delta;' +NL+
      '  float shadow_map_height = texture2D(castle_normal_map, shadow_texture_coord).a;' +NL+

      '  while (shadow_map_height < height && height < 1.0)' +NL+
      '  {' +NL+
      '    height += step;' +NL+
      '    shadow_texture_coord += delta;' +NL+
      '    shadow_map_height = texture2D(castle_normal_map, shadow_texture_coord).a;' +NL+
      '  }' +NL+

      '  if (shadow_map_height >= height)' +NL+
      '  {' +NL+
      '    /* TODO: setting appropriate light contribution to 0 would be more correct. But for now, this self-shadowing is hacky, always from light source 0, and after the light calculation is actually done. */' +NL+
      '    fragment_color.rgb /= 2.0;' +NL+
      '  }' +NL+
      '}';

  var
    VertexEyeBonusDeclarations, VertexEyeBonusCode, CoordName: string;
  begin
    if FBumpMapping = bmNone then Exit;

    VertexEyeBonusDeclarations := '';
    VertexEyeBonusCode := '';

    if FHeightMapInAlpha and (FBumpMapping >= bmParallax) then
    begin
      { parallax bump mapping }
      Plug(stFragment,
        'uniform float castle_parallax_bm_scale;' +NL+
        'uniform sampler2D castle_normal_map;' +NL+
        'varying vec3 castle_vertex_to_eye_in_tangent_space;' +NL+
        SteepParallaxDeclarations[FBumpMapping >= bmSteepParallax] +
        NL+
        'void PLUG_texture_coord_shift(inout vec2 tex_coord)' +NL+
        '{' +NL+
        { We have to normalize castle_vertex_to_eye_in_tangent_space again, just like normal vectors. }
        '  vec3 v_to_eye = normalize(castle_vertex_to_eye_in_tangent_space);' +NL+
        SteepParallaxShift[FBumpMapping >= bmSteepParallax] +
        '}');
      VertexEyeBonusDeclarations :=
        'varying vec3 castle_vertex_to_eye_in_tangent_space;' +NL;
      VertexEyeBonusCode :=
        'mat3 object_to_tangent_space = transpose(castle_tangent_to_object_space);' +NL+
        'mat3 eye_to_object_space = mat3(castle_ModelViewMatrix[0][0], castle_ModelViewMatrix[1][0], castle_ModelViewMatrix[2][0],' +NL+
        '                                castle_ModelViewMatrix[0][1], castle_ModelViewMatrix[1][1], castle_ModelViewMatrix[2][1],' +NL+
        '                                castle_ModelViewMatrix[0][2], castle_ModelViewMatrix[1][2], castle_ModelViewMatrix[2][2]);' +NL+
        'mat3 eye_to_tangent_space = object_to_tangent_space * eye_to_object_space;' +NL+
        { Theoretically faster implementation below, not fully correct ---
          assume that transpose is enough to invert this matrix. Tests proved:
          - results seem the same
          - but it's not really faster. }
        { 'mat3 eye_to_tangent_space = transpose(castle_tangent_to_eye_space);' +NL+ }
        'castle_vertex_to_eye_in_tangent_space = normalize(eye_to_tangent_space * (-vec3(vertex_eye)) );' +NL;

      BumpMappingUniformName2 := 'castle_parallax_bm_scale';
      BumpMappingUniformValue2 := FHeightMapScale;

      if (FBumpMapping >= bmSteepParallaxShadowing) and (LightShaders.Count > 0) then
      begin
        Plug(stFragment, SteepParallaxShadowing);
        VertexEyeBonusDeclarations +=
          'varying vec3 castle_light_direction_tangent_space;' +NL+
          // TODO: avoid redeclaring this when no "separate compilation units" (OpenGLES)
          'uniform vec3 castle_LightSource0Position;' +NL;

        { add VertexEyeBonusCode to cast shadow from LightShaders[0]. }
        VertexEyeBonusCode += 'vec3 light_dir = castle_LightSource0Position;';
        if LightShaders[0].Node is TAbstractPositionalLightNode then
          VertexEyeBonusCode += 'light_dir -= vec3(vertex_eye);';
          VertexEyeBonusCode +=
            'light_dir = normalize(light_dir);' +NL+
            'castle_light_direction_tangent_space = eye_to_tangent_space * light_dir;' +NL;
      end;
    end;

    Plug(stVertex,
      'attribute mat3 castle_tangent_to_object_space;' +NL+
      'varying mat3 castle_tangent_to_eye_space;' +NL+
      // TODO: avoid redeclaring this when no "separate compilation units" (OpenGLES)
      'uniform mat4 castle_ModelViewMatrix;' +NL+
      // TODO: avoid redeclaring this when no "separate compilation units" (OpenGLES)
      'uniform mat3 castle_NormalMatrix;' +NL+
      VertexEyeBonusDeclarations +
      NL+
      'void PLUG_vertex_eye_space(const in vec4 vertex_eye, const in vec3 normal_eye)' +NL+
      '{' +NL+
      '  castle_tangent_to_eye_space = castle_NormalMatrix * castle_tangent_to_object_space;' +NL+
      VertexEyeBonusCode +
      '}');

    CoordName := TTextureCoordinateShader.CoordName(FNormalMapTextureCoordinatesId);

    Plug(stFragment,
      'varying mat3 castle_tangent_to_eye_space;' +NL+
      'uniform sampler2D castle_normal_map;' +NL+
      'varying vec4 ' + CoordName + ';' +NL+
      NL+
      'void PLUG_fragment_eye_space(const vec4 vertex, inout vec3 normal_eye_fragment)' +NL+
      '{' +NL+
      { Read normal from the texture, this is the very idea of bump mapping.
        Unpack normals, they are in texture in [0..1] range and I want in [-1..1]. }
      '  vec3 normal_tangent = texture2D(castle_normal_map, ' + CoordName + '.st).xyz * 2.0 - vec3(1.0);' +NL+

      '  /* We have to take two-sided lighting into account here, in tangent space.' +NL+
      '     Simply negating whole normal in eye space (like we do without bump mapping)' +NL+
      '     would not work good, check e.g. insides of demo_models/bump_mapping/room_for_parallax_final.wrl. */' +NL+
      '  if (gl_FrontFacing)' +NL+
      '    /* Avoid AMD bug http://forums.amd.com/devforum/messageview.cfm?catid=392&threadid=148827&enterthread=y' +NL+
      '       It causes both (gl_FrontFacing) and (!gl_FrontFacing) to be true...' +NL+
      '       To minimize the number of problems, never use "if (!gl_FrontFacing)",' +NL+
      '       only "if (gl_FrontFacing)".' +NL+
      '       See template.fs for more comments.' +NL+
      '    */ ; else' +NL+
      '    normal_tangent.z = -normal_tangent.z;' +NL+

      '  normal_eye_fragment = normalize(castle_tangent_to_eye_space * normal_tangent);' +NL+
      '}');

    BumpMappingUniformName1 := 'castle_normal_map';
    BumpMappingUniformValue1 := FNormalMapTextureUnit;
  end;

  { Must be done after EnableLights (to add define COLOR_PER_VERTEX
    also to light shader parts). }
  procedure EnableShaderMaterialFromColor;
  begin
    if MaterialFromColor then
    begin
      { TODO: need to pass castle_ColorPerVertexFragment onward?
      Plug(stGeometry, GeometryShaderPassColors);
      }

      Define('COLOR_PER_VERTEX', stVertex);
      Define('COLOR_PER_VERTEX', stFragment);
    end;
  end;

  procedure EnableShaderSurfaceTextures;
  const
    PlugFunction: array [TSurfaceTexture] of string =
    (
      'uniform sampler2D %s;' +NL+
      // TODO: avoid redeclaring this when no "separate compilation units" (OpenGLES)
      'varying vec4 %s;' + NL+
      'void PLUG_material_light_ambient(inout vec4 ambient)' +NL+
      '{' +NL+
      '  ambient.rgb *= texture2D(%s, %s.st).%s;' +NL+
      '}' +NL,

      'uniform sampler2D %s;' +NL+
      // TODO: avoid redeclaring this when no "separate compilation units" (OpenGLES)
      'varying vec4 %s;' + NL+
      'void PLUG_material_light_specular(inout vec4 specular)' +NL+
      '{' +NL+
      '  specular.rgb *= texture2D(%s, %s.st).%s;' +NL+
      '}' +NL,

      'uniform sampler2D %s;' +NL+
      // TODO: avoid redeclaring this when no "separate compilation units" (OpenGLES)
      'varying vec4 %s;' + NL+
      'void PLUG_material_shininess(inout float shininess)' +NL+
      '{' +NL+
      '  shininess *= texture2D(%s, %s.st).%s;' +NL+
      '}' +NL
    );
  var
    SurfaceTexture: TSurfaceTexture;
    CoordName, UniformTextureName: string;
  begin
    for SurfaceTexture in TSurfaceTexture do
      if FSurfaceTextureShaders[SurfaceTexture].Enable then
      begin
        UniformTextureName := TSurfaceTextureShader.UniformTextureName(SurfaceTexture);
        CoordName := TTextureCoordinateShader.CoordName(FSurfaceTextureShaders[SurfaceTexture].TextureCoordinatesId);
        Plug(stFragment, Format(PlugFunction[SurfaceTexture],
          [ UniformTextureName,
            CoordName,
            UniformTextureName,
            CoordName,
            FSurfaceTextureShaders[SurfaceTexture].ChannelMask ]));
      end;
  end;

  procedure EnableShaderFog;
  var
    FogFactor, FogUniforms, CoordinateSource: string;
    USingle: TDynamicUniformSingle;
    UColor: TDynamicUniformVec3;
  begin
    { Both OpenGLES and desktop OpenGL use castle_xxx uniforms and varying
      to pass fog parameters, not gl_xxx. }

    if FFogEnabled then
    begin
      case FFogCoordinateSource of
        fcDepth           : CoordinateSource := '-vertex_eye.z';
        fcPassedCoordinate: CoordinateSource := 'castle_FogCoord';
        else raise EInternalError.Create('TShader.EnableShaderFog:FogCoordinateSource?');
      end;

      Plug(stVertex,
        'attribute float castle_FogCoord;' +NL+
        'varying float castle_FogFragCoord;' + NL+
        'void PLUG_vertex_eye_space(const in vec4 vertex_eye, const in vec3 normal_eye)' +NL+
        '{' +NL+
        '  castle_FogFragCoord = ' + CoordinateSource + ';' +NL+
        '}');

      case FFogType of
        ftLinear:
          begin
            FogUniforms := 'uniform float castle_FogLinearEnd;';
            { The fixed-function fog equation multiply by gl_Fog.scale,
              which is a precomputed 1.0 / (gl_Fog.end - gl_Fog.start),
              which is just 1.0 / gl_Fog.end for us.
              So we just divide by castle_FogLinearEnd. }
            FogFactor := 'castle_FogFragCoord / castle_FogLinearEnd';

            USingle := TDynamicUniformSingle.Create;
            USingle.Name := 'castle_FogLinearEnd';
            USingle.Value := FFogLinearEnd;
            DynamicUniforms.Add(USingle);
          end;
        ftExp:
          begin
            FogUniforms := 'uniform float castle_FogExpDensity;';
            FogFactor := '1.0 - exp(-castle_FogExpDensity * castle_FogFragCoord)';

            USingle := TDynamicUniformSingle.Create;
            USingle.Name := 'castle_FogExpDensity';
            USingle.Value := FFogExpDensity;
            DynamicUniforms.Add(USingle);
          end;
        else raise EInternalError.Create('TShader.EnableShaderFog:FogType?');
      end;

      UColor := TDynamicUniformVec3.Create;
      UColor.Name := 'castle_FogColor';
      UColor.Value := FFogColor;
      { We leave UColor.Declaration empty, just like USingle.Declaration above,
        because we only declare them inside this plug
        (which is a separate compilation unit for desktop OpenGL). }
      DynamicUniforms.Add(UColor);
      Plug(stFragment,
        'varying float castle_FogFragCoord;' + NL+
        'uniform vec3 castle_FogColor;' +NL+
        FogUniforms + NL +
        'void PLUG_fog_apply(inout vec4 fragment_color, const vec3 normal_eye_fragment)' +NL+
        '{' +NL+
        '  fragment_color.rgb = mix(fragment_color.rgb, castle_FogColor,' +NL+
        '    clamp(' + FogFactor + ', 0.0, 1.0));' +NL+
        '}');
    end;
  end;

  procedure SetupUniformsOnce;
  var
    I: Integer;
    SurfaceTexture: TSurfaceTexture;
  begin
    AProgram.Enable;

    if TextureUniformsSet then
    begin
      for I := 0 to TextureShaders.Count - 1 do
        if (TextureShaders[I] is TTextureShader) and
           (TTextureShader(TextureShaders[I]).UniformName <> '') then
          AProgram.SetUniform(TTextureShader(TextureShaders[I]).UniformName,
                              TTextureShader(TextureShaders[I]).UniformValue);
    end;

    if BumpMappingUniformName1 <> '' then
      AProgram.SetUniform(BumpMappingUniformName1,
                          BumpMappingUniformValue1);

    if BumpMappingUniformName2 <> '' then
      AProgram.SetUniform(BumpMappingUniformName2,
                          BumpMappingUniformValue2);

    for SurfaceTexture in TSurfaceTexture do
      if FSurfaceTextureShaders[SurfaceTexture].Enable then
        AProgram.SetUniform(
          TSurfaceTextureShader.UniformTextureName(SurfaceTexture),
          Integer(FSurfaceTextureShaders[SurfaceTexture].TextureUnit));

    AProgram.BindUniforms(UniformsNodes, false);

    if PassLightsUniforms then
      for I := 0 to LightShaders.Count - 1 do
        LightShaders[I].SetUniforms(AProgram);

    AProgram.Disable;
  end;

var
  ShaderType: TShaderType;
  I: Integer;
  GeometryInputSize, LogStr, LogStrPart: string;
begin
  RequireTextureCoordinateForSurfaceTextures;
  EnableTextures;
  EnableInternalEffects;
  EnableLights;
  EnableShaderMaterialFromColor;
  {$ifndef OpenGLES} //TODO-es
  EnableShaderBumpMapping;
  EnableShaderSurfaceTextures;
  {$endif}
  EnableShaderFog;
  if AppearanceEffects <> nil then
    EnableEffects(AppearanceEffects);
  if GroupEffects <> nil then
    EnableEffects(GroupEffects);

  if HasGeometryMain then
  begin
    Define('HAS_GEOMETRY_SHADER', stFragment);
    if GLVersion.VendorType = gvATI then
      GeometryInputSize := 'gl_in.length()' else
      GeometryInputSize := '';
    { Replace CASTLE_GEOMETRY_INPUT_SIZE }
    for I := 0 to Source[stGeometry].Count - 1 do
      Source[stGeometry][I] := StringReplace(Source[stGeometry][I],
        'CASTLE_GEOMETRY_INPUT_SIZE', GeometryInputSize, [rfReplaceAll]);
  end else
    Source[stGeometry].Clear;

  if GLVersion.BuggyGLSLFrontFacing then
    Define('CASTLE_BUGGY_FRONT_FACING', stFragment);

  if GLVersion.BuggyGLSLReadVarying then
    Define('CASTLE_BUGGY_GLSL_READ_VARYING', stVertex);

  if Log and LogShaders then
  begin
    LogStr :=
      '# Generated shader code for shape ' + ShapeNiceName + ' by ' + ApplicationName + '.' + NL +
      '# To try this out, paste this inside Appearance node in VRML/X3D classic encoding.' + NL +
      'shaders ComposedShader {' + NL +
      '  language "GLSL"' + NL +
      '  parts [' + NL;
    for ShaderType := Low(ShaderType) to High(ShaderType) do
      for I := 0 to Source[ShaderType].Count - 1 do
      begin
        LogStrPart := Source[ShaderType][I];
        LogStrPart := StringReplace(LogStrPart, '/* PLUG:', '/* ALREADY-PROCESSED-PLUG:', [rfReplaceAll]);
        LogStrPart := StringReplace(LogStrPart, '/* PLUG-DECLARATIONS */', '/* ALREADY-PROCESSED-PLUG-DECLARATIONS */', [rfReplaceAll]);
        LogStr += '    ShaderPart { type "' + ShaderTypeNameX3D[ShaderType] +
          '" url "data:text/plain,' +
          StringToX3DClassic(LogStrPart, false) + '"' + NL +
          '    }';
      end;
    LogStr += '  ]' + NL + '}';
    WritelnLogMultiline('Generated Shader', LogStr);
  end;

  try
    if (Source[stVertex].Count = 0) and
       (Source[stFragment].Count = 0) then
      raise EGLSLError.Create('No vertex and no fragment shader for GLSL program');

    for ShaderType := Low(ShaderType) to High(ShaderType) do
      AProgram.AttachShader(ShaderType, Source[ShaderType]);
    AProgram.Link;

    if SelectedNode <> nil then
      SelectedNode.EventIsValid.Send(true);
  except
    if SelectedNode <> nil then
      SelectedNode.EventIsValid.Send(false);
    raise;
  end;

  { All user VRML/X3D uniform values go through SetUniformFromField,
    that always raises exception on invalid names/types, regardless
    of UniformNotFoundAction / UniformTypeMismatchAction values.

    So settings below only control what happens on our uniform values.
    - Missing uniform name should be ignored, as it's normal in some cases:
      - When ShadowVisualizeDepth is used, almost everything (besides
        the single visualized shadow map) is unused.
      - When all the lights are off (including headlight) then normal vectors
        are unused, and so the normalmap texture is unused.

      Avoid producing any warnings in this case, as this is normal situation.
      Actually needed at least on NVidia GeForce 450 GTS (proprietary OpenGL
      under Linux), on ATI (tested proprietary OpenGL drivers under Linux and Windows)
      this doesn't seem needed (less aggressive removal of unused vars).

    - Invalid types should always be reported in debug mode, as OpenGL errors.
      This is the fastest option (other values for UniformTypeMismatchAction
      are not good for performance, causing glGetError around every
      TGLSLUniform.SetValue call, very very slow). We carefully code to
      always specify correct types for our uniform variables. }
  AProgram.UniformNotFoundAction := uaIgnore;
  AProgram.UniformTypeMismatchAction := utGLError;

  { set uniforms that will not need to be updated at each SetupUniforms call }
  SetupUniformsOnce;
end;

procedure TShader.LinkFallbackProgram(AProgram: TX3DShaderProgram);
const
  VS = {$I fallback.vs.inc};
  FS = {$I fallback.fs.inc};
begin
  if Log and LogShaders then
    WritelnLogMultiline('Using Fallback GLSL shaders',
      'Fallback vertex shader:' + NL +  VS + NL +
      'Fallback fragment shader:' + NL + FS);
  AProgram.AttachShader(stVertex, VS);
  AProgram.AttachShader(stFragment, FS);
  AProgram.Link;

  AProgram.UniformNotFoundAction := uaIgnore;
  AProgram.UniformTypeMismatchAction := utGLError;
end;

function TShader.CodeHash: TShaderCodeHash;

  { Add to FCodeHash some stuff that must be added at the end,
    since it can be changed back (replacing previous values) during TShader
    lifetime. }
  procedure CodeHashFinalize;
  begin
    FCodeHash.AddInteger(Ord(ShadowSampling) * 1009);
  end;

begin
  if not CodeHashFinalized then
  begin
    CodeHashFinalize;
    CodeHashFinalized := true;
  end;
  Result := FCodeHash;
end;

procedure TShader.EnableTexture(const TextureUnit: Cardinal;
  const TextureType: TTextureType;
  const Node: TAbstractTextureNode;
  const Env: TTextureEnv;
  const ShadowMapSize: Cardinal;
  const ShadowLight: TAbstractLightNode;
  const ShadowVisualizeDepth: boolean);
var
  TextureShader: TTextureShader;
begin
  { Enable for fixed-function pipeline }
  if GLFeatures.UseMultiTexturing then
    glActiveTexture(GL_TEXTURE0 + TextureUnit);
  case TextureType of
    tt2D, tt2DShadow: GLEnableTexture(et2D);
    ttCubeMap       : GLEnableTexture(etCubeMap);
    tt3D            : GLEnableTexture(et3D);
    ttShader        : GLEnableTexture(etNone);
    else raise EInternalError.Create('TextureEnableDisable?');
  end;

  { Enable for shader pipeline }

  TextureShader := TTextureShader.Create;
  TextureShader.HasMatrixTransform :=
    (TextureMatrix.IndexOf(TextureUnit) <> -1)
    and not (GLVersion.BuggyShaderShadowMap and (TextureType = tt2DShadow));
  TextureShader.TextureUnit := TextureUnit;
  TextureShader.TextureType := TextureType;
  TextureShader.Node := Node;
  TextureShader.Env := Env;
  TextureShader.ShadowMapSize := ShadowMapSize;
  TextureShader.ShadowLight := ShadowLight;
  TextureShader.ShadowVisualizeDepth := ShadowVisualizeDepth;
  TextureShader.Shader := Self;

  TextureShaders.Add(TextureShader);

  if (TextureType in [ttShader, tt2DShadow]) or
     (Node.FdEffects.Count <> 0) or
     { MultiTexture.function requires shaders }
     (Env.TextureFunction <> tfNone) then
    ShapeRequiresShaders := true;

  TextureShader.Prepare(FCodeHash);
end;

procedure TShader.EnableTexGen(const TextureUnit: Cardinal;
  const Generation: TTexGenerationComplete;
  const TransformToWorldSpace: boolean);
var
  TexCoordName: string;
begin
  { Enable for fixed-function pipeline }
  if GLFeatures.UseMultiTexturing then
    glActiveTexture(GL_TEXTURE0 + TextureUnit);
  { Rest of code code fixed-function pipeline
    (glTexGeni and glEnable(GL_TEXTURE_GEN_*)) is below }

  TexCoordName := TTextureShader.CoordName(TextureUnit);

  { Enable for fixed-function and shader pipeline }
  case Generation of
    tgSphere:
      begin
        if EnableFixedFunction then
        begin
          {$ifndef OpenGLES}
          glTexGeni(GL_S, GL_TEXTURE_GEN_MODE, GL_SPHERE_MAP);
          glTexGeni(GL_T, GL_TEXTURE_GEN_MODE, GL_SPHERE_MAP);
          glEnable(GL_TEXTURE_GEN_S);
          glEnable(GL_TEXTURE_GEN_T);
          {$endif}
        end;
        TextureCoordGen += Format(
          { Sphere mapping in GLSL adapted from
            http://www.ozone3d.net/tutorials/glsl_texturing_p04.php#part_41
            by Jerome Guinot aka 'JeGX', many thanks! }
          'vec3 r = reflect( normalize(vec3(castle_vertex_eye)), castle_normal_eye );' + NL +
          'float m = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );' + NL +
          '/* Using 1.0 / 2.0 instead of 0.5 to workaround fglrx bugs */' + NL +
          '%s.st = r.xy / m + vec2(1.0, 1.0) / 2.0;',
          [TexCoordName]);
        FCodeHash.AddInteger(1301 * (TextureUnit + 1));
      end;
    tgNormal:
      begin
        if EnableFixedFunction then
        begin
          {$ifndef OpenGLES}
          glTexGeni(GL_S, GL_TEXTURE_GEN_MODE, GL_NORMAL_MAP_ARB);
          glTexGeni(GL_T, GL_TEXTURE_GEN_MODE, GL_NORMAL_MAP_ARB);
          glTexGeni(GL_R, GL_TEXTURE_GEN_MODE, GL_NORMAL_MAP_ARB);
          glEnable(GL_TEXTURE_GEN_S);
          glEnable(GL_TEXTURE_GEN_T);
          glEnable(GL_TEXTURE_GEN_R);
          {$endif}
        end;
        TextureCoordGen += Format('%s.xyz = castle_normal_eye;' + NL,
          [TexCoordName]);
        FCodeHash.AddInteger(1303 * (TextureUnit + 1));
      end;
    tgReflection:
      begin
        if EnableFixedFunction then
        begin
          {$ifndef OpenGLES}
          glTexGeni(GL_S, GL_TEXTURE_GEN_MODE, GL_REFLECTION_MAP_ARB);
          glTexGeni(GL_T, GL_TEXTURE_GEN_MODE, GL_REFLECTION_MAP_ARB);
          glTexGeni(GL_R, GL_TEXTURE_GEN_MODE, GL_REFLECTION_MAP_ARB);
          glEnable(GL_TEXTURE_GEN_S);
          glEnable(GL_TEXTURE_GEN_T);
          glEnable(GL_TEXTURE_GEN_R);
          {$endif}
        end;
        { Negate reflect result --- just like for demo_models/water/water_reflections_normalmap.fs }
        TextureCoordGen += Format('%s.xyz = -reflect(-vec3(castle_vertex_eye), castle_normal_eye);' + NL,
          [TexCoordName]);
        FCodeHash.AddInteger(1307 * (TextureUnit + 1));
      end;
    else raise EInternalError.Create('TShader.EnableTexGen:Generation?');
  end;

  if TransformToWorldSpace then
  begin
    TextureCoordGen += Format('%s.w = 0.0; %0:s = castle_CameraInverseMatrix * %0:s;' + NL,
      [TexCoordName]);
    NeedsCameraInverseMatrix := true;
    FCodeHash.AddInteger(263);
  end;
end;

procedure TShader.EnableTexGen(const TextureUnit: Cardinal;
  const Generation: TTexGenerationComponent; const Component: TTexComponent;
  const Plane: TVector4);
const
  PlaneComponentNames: array [TTexComponent] of char = ('S', 'T', 'R', 'Q');
  { Note: R changes to p ! }
  VectorComponentNames: array [TTexComponent] of char = ('s', 't', 'p', 'q');
var
  PlaneName, CoordSource, TexCoordName: string;
  Uniform: TDynamicUniformVec4;
begin
  { Enable for fixed-function pipeline }
  if GLFeatures.UseMultiTexturing then
    glActiveTexture(GL_TEXTURE0 + TextureUnit);

  if EnableFixedFunction then
  begin
    {$ifndef OpenGLES}
    case Component of
      0: glEnable(GL_TEXTURE_GEN_S);
      1: glEnable(GL_TEXTURE_GEN_T);
      2: glEnable(GL_TEXTURE_GEN_R);
      3: glEnable(GL_TEXTURE_GEN_Q);
      else raise EInternalError.Create('TShader.EnableTexGen:Component?');
    end;
    {$endif}
  end;

  { Enable for shader pipeline.
    See helpful info about simulating glTexGen in GLSL in:
    http://www.mail-archive.com/osg-users@lists.openscenegraph.org/msg14238.html }

  case Generation of
    tgEye   : begin PlaneName := 'EyePlane'   ; CoordSource := 'castle_vertex_eye'; end;
    tgObject: begin PlaneName := 'ObjectPlane'; CoordSource := 'vertex_object' ; end;
    else raise EInternalError.Create('TShader.EnableTexGen:Generation?');
  end;

  PlaneName := 'castle_' + PlaneName + PlaneComponentNames[Component] +
    Format('%d', [TextureUnit]);

  Uniform := TDynamicUniformVec4.Create;
  Uniform.Name := PlaneName;
  Uniform.Declaration := 'uniform vec4 ' + PlaneName + ';' + NL;
  Uniform.Value := Plane;
  DynamicUniforms.Add(Uniform);

  TexCoordName := TTextureShader.CoordName(TextureUnit);
  TextureCoordGen += Format('%s.%s = dot(%s, %s);' + NL,
    [TexCoordName, VectorComponentNames[Component], CoordSource, PlaneName]);
  FCodeHash.AddInteger(1319 * (TextureUnit + 1) * (Ord(Generation) + 1) * (Component + 1));
end;

procedure TShader.DisableTexGen(const TextureUnit: Cardinal);
begin
  if EnableFixedFunction then
  begin
    { Disable for fixed-function pipeline }
    if GLFeatures.UseMultiTexturing then
      glActiveTexture(GL_TEXTURE0 + TextureUnit);
    {$ifndef OpenGLES}
    glDisable(GL_TEXTURE_GEN_S);
    glDisable(GL_TEXTURE_GEN_T);
    glDisable(GL_TEXTURE_GEN_R);
    glDisable(GL_TEXTURE_GEN_Q);
    {$endif}
  end;
end;

procedure TShader.EnableTextureTransform(const TextureUnit: Cardinal;
  const Matrix: TMatrix4);
var
  Uniform: TDynamicUniformMat4;
begin
  { pass the uniform value with transformation to shader }
  Uniform := TDynamicUniformMat4.Create;
  Uniform.Name := TTextureShader.MatrixName(TextureUnit);
  Uniform.Declaration := 'uniform mat4 ' + Uniform.Name + ';' + NL;
  Uniform.Value := Matrix;
  DynamicUniforms.Add(Uniform);

  { multiply by the uniform value in shader }
  TextureMatrix.Add(TextureUnit);

  FCodeHash.AddInteger(1973 * (TextureUnit + 1));
end;

procedure TShader.EnableClipPlane(const ClipPlaneIndex: Cardinal);
begin
  {$ifndef OpenGLES}
  // TODO-es how to do it on OpenGLES?
  glEnable(GL_CLIP_PLANE0 + ClipPlaneIndex);
  {$endif}
  if ClipPlane = '' then
  begin
    ClipPlane := 'gl_ClipVertex = castle_vertex_eye;';

    (* TODO: make this work: (instead of 0, add each index)
    ClipPlaneGeometryPlug :=
      '#version 150 compatibility' +NL+
      'void PLUG_geometry_vertex_set(const int index)' +NL+
      '{' +NL+
      '  gl_ClipDistance[0] = gl_in[index].gl_ClipDistance[0];' +NL+
      '}' +NL+
      'void PLUG_geometry_vertex_zero()' +NL+
      '{' +NL+
      '  gl_ClipDistance[0] = 0.0;' +NL+
      '}' +NL+
      'void PLUG_geometry_vertex_add(const int index, const float scale)' +NL+
      '{' +NL+
      '  gl_ClipDistance[0] += gl_in[index].gl_ClipDistance[0] * scale;' +NL+
      '}' +NL;
    *)
    FCodeHash.AddInteger(2003);
  end;
end;

procedure TShader.DisableClipPlane(const ClipPlaneIndex: Cardinal);
begin
  {$ifndef OpenGLES}
  glDisable(GL_CLIP_PLANE0 + ClipPlaneIndex);
  {$endif}
end;

procedure TShader.EnableAlphaTest;
begin
  { Enable for shader pipeline. We know alpha comparison is always < 0.5 }
  FragmentEnd +=
    '/* Do the trick with 1.0 / 2.0, instead of comparing with 0.5, to avoid fglrx bugs */' + NL +
    'if (2.0 * gl_FragColor.a < 1.0)' + NL +
    '  discard;' + NL;

  FCodeHash.AddInteger(2011);
end;

procedure TShader.EnableBumpMapping(const BumpMapping: TBumpMapping;
  const NormalMapTextureUnit, NormalMapTextureCoordinatesId: Cardinal;
  const HeightMapInAlpha: boolean; const HeightMapScale: Single);
begin
  FBumpMapping := BumpMapping;
  FNormalMapTextureUnit := NormalMapTextureUnit;
  FNormalMapTextureCoordinatesId := NormalMapTextureCoordinatesId;
  FHeightMapInAlpha := HeightMapInAlpha;
  FHeightMapScale := HeightMapScale;

  if FBumpMapping <> bmNone then
  begin
    ShapeRequiresShaders := true;
    FCodeHash.AddInteger(
      47 * Ord(FBumpMapping) +
      373 * FNormalMapTextureUnit +
      379 * FNormalMapTextureCoordinatesId +
      383 * Ord(FHeightMapInAlpha)
    );
    FCodeHash.AddFloat(FHeightMapScale);
  end;
end;

procedure TShader.EnableSurfaceTexture(const SurfaceTexture: TSurfaceTexture;
  const TextureUnit, TextureCoordinatesId: Cardinal;
  const ChannelMask: string);
var
  HashMultiplier: LongWord;
begin
  FSurfaceTextureShaders[SurfaceTexture].Enable := true;
  FSurfaceTextureShaders[SurfaceTexture].TextureUnit := TextureUnit;
  FSurfaceTextureShaders[SurfaceTexture].TextureCoordinatesId := TextureCoordinatesId;
  FSurfaceTextureShaders[SurfaceTexture].ChannelMask := ChannelMask;

  ShapeRequiresShaders := true;

  HashMultiplier := 2063 * (1 + Ord(SurfaceTexture));
  FCodeHash.AddInteger(HashMultiplier * (
    2069 * TextureUnit +
    2081 * TextureCoordinatesId
  ));
  FCodeHash.AddString(ChannelMask, 2083 * HashMultiplier);
end;

procedure TShader.EnableLight(const Number: Cardinal; Light: PLightInstance);
var
  LightShader: TLightShader;
begin
  LightShader := TLightShader.Create;
  LightShader.Number := Number;
  LightShader.Light := Light;
  LightShader.Node := Light^.Node;
  LightShader.Shader := Self;

  LightShaders.Add(LightShader);

  if Light^.Node.FdEffects.Count <> 0 then
    ShapeRequiresShaders := true;

  LightShader.Prepare(FCodeHash, LightShaders.Count - 1);
end;

procedure TShader.EnableFog(const FogType: TFogType;
  const FogCoordinateSource: TFogCoordinateSource;
  const FogColor: TVector3; const FogLinearEnd: Single;
  const FogExpDensity: Single);
begin
  FFogEnabled := true;
  FFogType := FogType;
  FFogCoordinateSource := FogCoordinateSource;
  FFogColor := FogColor;
  FFogLinearEnd := FogLinearEnd;
  FFogExpDensity := FogExpDensity;
  FCodeHash.AddInteger(
    67 * (Ord(FFogType) + 1) +
    709 * (Ord(FFogCoordinateSource) + 1));
end;

procedure TShader.ModifyFog(const FogType: TFogType;
  const FogCoordinateSource: TFogCoordinateSource;
  const FogLinearEnd: Single; const FogExpDensity: Single);
begin
  { Do not enable fog, or change it's color. Only work if fog already enabled. }
  FFogType := FogType;
  FFogCoordinateSource := FogCoordinateSource;
  FFogLinearEnd := FogLinearEnd;
  FFogExpDensity := FogExpDensity;

  FCodeHash.AddInteger(
    431 * (Ord(FFogType) + 1) +
    433 * (Ord(FFogCoordinateSource) + 1));
end;

function TShader.EnableCustomShaderCode(Shaders: TMFNodeShaders;
  out Node: TComposedShaderNode): boolean;
var
  I, J: Integer;
  Part: TShaderPartNode;
  PartSource: String;
  PartType, SourceType: TShaderType;
begin
  Result := false;
  for I := 0 to Shaders.Count - 1 do
  begin
    Node := Shaders.GLSLShader(I);
    if Node <> nil then
    begin
      Result := true;

      { Clear whole Source }
      for SourceType := Low(SourceType) to High(SourceType) do
        if SourceType <> stGeometry then
          Source[SourceType].Count := 0;

      { Iterate over Node.FdParts, looking for vertex shaders
        and fragment shaders. }
      for J := 0 to Node.FdParts.Count - 1 do
        if Node.FdParts[J] is TShaderPartNode then
        begin
          Part := TShaderPartNode(Node.FdParts[J]);
          PartSource := Part.Contents;
          if PartSource <> '' then
          begin
            PartType := Part.ShaderType;
            Source[PartType].Add(PartSource);
            if PartType = stGeometry then
              HasGeometryMain := true;
          end;
        end;

      Node.EventIsSelected.Send(true);

      UniformsNodes.Add(Node);

      { For sending isValid to this node later }
      SelectedNode := Node;

      { Ignore missing plugs, as our plugs are (probably) not found there }
      WarnMissingPlugs := false;

      ShapeRequiresShaders := true;

      { We add to FCodeHash custom shader node.

        We don't add the source code (all PartSource), we just add node
        reference, for reasoning see TShaderCodeHash.AddEffects (equal
        source code may still mean different uniforms).
        Also, adding a node reference is faster that calculating string hash.

        Note that our original shader code (from glsl/template*)
        is never added to hash --- there's no need, after all it's
        always constant. }
      FCodeHash.AddPointer(Node);

      Break;
    end else
    if Shaders[I] is TAbstractShaderNode then
      TAbstractShaderNode(Shaders[I]).EventIsSelected.Send(false);
  end;
end;

procedure TShader.EnableAppearanceEffects(Effects: TMFNode);
begin
  AppearanceEffects := Effects;
  if AppearanceEffects.Count <> 0 then
  begin
    ShapeRequiresShaders := true;
    FCodeHash.AddEffects(AppearanceEffects.Items);
  end;
end;

procedure TShader.EnableGroupEffects(Effects: TX3DNodeList);
begin
  GroupEffects := Effects;
  if GroupEffects.Count <> 0 then
  begin
    ShapeRequiresShaders := true;
    FCodeHash.AddEffects(GroupEffects);
  end;
end;

procedure TShader.EnableLighting;
begin
  Lighting := true;
  FCodeHash.AddInteger(7);
end;

procedure TShader.EnableMaterialFromColor;
begin
  if EnableFixedFunction then
  begin
    { glColorMaterial is already set by TGLRenderer.RenderBegin }
    {$ifndef OpenGLES}
    glEnable(GL_COLOR_MATERIAL);
    {$endif}
  end;

  { This will cause appropriate shader later }
  MaterialFromColor := true;
  FCodeHash.AddInteger(29);
end;

function TShader.DeclareShadowFunctions: string;
const
  ShadowDeclare: array [boolean { vsm? }] of string =
  ('float shadow(sampler2DShadow shadowMap, const vec4 shadowMapCoord, const in float size);',
   'float shadow(sampler2D       shadowMap, const vec4 shadowMapCoord, const in float size);');
  ShadowDepthDeclare =
   'float shadow_depth(sampler2D shadowMap, const vec4 shadowMapCoord);';
begin
  Result := ShadowDeclare[ShadowSampling = ssVarianceShadowMaps] + NL + ShadowDepthDeclare;
end;

procedure TShader.SetDynamicUniforms(AProgram: TX3DShaderProgram);
var
  I: Integer;
begin
  for I := 0 to LightShaders.Count - 1 do
    LightShaders[I].SetDynamicUniforms(AProgram);
  for I := 0 to DynamicUniforms.Count - 1 do
    DynamicUniforms[I].SetUniform(AProgram);
  if NeedsCameraInverseMatrix then
  begin
    RenderingCamera.InverseMatrixNeeded;
    AProgram.SetUniform('castle_CameraInverseMatrix', RenderingCamera.InverseMatrix);
  end;
end;

procedure TShader.AddScreenEffectCode(const Depth: boolean);
var
  VS, FS: string;
begin
  VS := ScreenEffectVertex;
  FS := ScreenEffectFragment(Depth);

  Source[stVertex].Insert(0, VS);
  { For OpenGLES, ScreenEffectLibrary must be 1st shader,
    and it will be glued with the user shader code.
    So we glue it also on desktop OpenGL, for consistency
    (so e.g. you should never repeat "uniform screen_width...").  }
  if Source[stFragment].Count <> 0 then
    Source[stFragment][0] := FS + Source[stFragment][0] else
    Source[stFragment].Insert(0, FS);
end;

end.
