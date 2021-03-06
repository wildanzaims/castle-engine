{ -*- buffer-read-only: t -*-

  Copyright 2015-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automatically generated node properties.

  Do not edit this file manually!
  To add new properties:
  - add them to the text files in tools/internal/x3d-nodes-to-pascal/nodes-specification/ ,
  - and regenerate include files by running x3d-nodes-to-pascal .

  The documentation for properties should go to x3dnodes_documentation.txt . }

{$ifdef read_interface}

  strict private
    function GetAutoDisable: boolean;
    procedure SetAutoDisable(const Value: boolean);
    function GetConstantForceMix: Single;
    procedure SetConstantForceMix(const Value: Single);
    function GetContactSurfaceThickness: Single;
    procedure SetContactSurfaceThickness(const Value: Single);
    function GetDisableAngularSpeed: Single;
    procedure SetDisableAngularSpeed(const Value: Single);
    function GetDisableLinearSpeed: Single;
    procedure SetDisableLinearSpeed(const Value: Single);
    function GetDisableTime: Single;
    procedure SetDisableTime(const Value: Single);
    function GetEnabled: boolean;
    procedure SetEnabled(const Value: boolean);
    function GetErrorCorrection: Single;
    procedure SetErrorCorrection(const Value: Single);
    function GetGravity: TVector3;
    procedure SetGravity(const Value: TVector3);
    function GetIterations: Integer;
    procedure SetIterations(const Value: Integer);
    function GetMaxCorrectionSpeed: Single;
    procedure SetMaxCorrectionSpeed(const Value: Single);
    function GetPreferAccuracy: boolean;
    procedure SetPreferAccuracy(const Value: boolean);
    function GetCollider: TCollisionCollectionNode;
    procedure SetCollider(const Value: TCollisionCollectionNode);
  public
    { X3D field "autoDisable". } { }
    property AutoDisable: boolean read GetAutoDisable write SetAutoDisable;
    { Set X3D field "bodies". } { }
    procedure SetBodies(const Value: array of TRigidBodyNode);
    { X3D field "constantForceMix". } { }
    property ConstantForceMix: Single read GetConstantForceMix write SetConstantForceMix;
    { X3D field "contactSurfaceThickness". } { }
    property ContactSurfaceThickness: Single read GetContactSurfaceThickness write SetContactSurfaceThickness;
    { X3D field "disableAngularSpeed". } { }
    property DisableAngularSpeed: Single read GetDisableAngularSpeed write SetDisableAngularSpeed;
    { X3D field "disableLinearSpeed". } { }
    property DisableLinearSpeed: Single read GetDisableLinearSpeed write SetDisableLinearSpeed;
    { X3D field "disableTime". } { }
    property DisableTime: Single read GetDisableTime write SetDisableTime;
    { X3D field "enabled". } { }
    property Enabled: boolean read GetEnabled write SetEnabled;
    { X3D field "errorCorrection". } { }
    property ErrorCorrection: Single read GetErrorCorrection write SetErrorCorrection;
    { X3D field "gravity". } { }
    property Gravity: TVector3 read GetGravity write SetGravity;
    { X3D field "iterations". } { }
    property Iterations: Integer read GetIterations write SetIterations;
    { Set X3D field "joints". } { }
    procedure SetJoints(const Value: array of TAbstractRigidJointNode);
    { X3D field "maxCorrectionSpeed". } { }
    property MaxCorrectionSpeed: Single read GetMaxCorrectionSpeed write SetMaxCorrectionSpeed;
    { X3D field "preferAccuracy". } { }
    property PreferAccuracy: boolean read GetPreferAccuracy write SetPreferAccuracy;
    { X3D field "collider". } { }
    property Collider: TCollisionCollectionNode read GetCollider write SetCollider;

{$endif read_interface}

{$ifdef read_implementation}

{ TRigidBodyCollectionNode ----------------------------------------------- }

function TRigidBodyCollectionNode.GetAutoDisable: boolean;
begin
  Result := FdAutoDisable.Value;
end;

procedure TRigidBodyCollectionNode.SetAutoDisable(const Value: boolean);
begin
  FdAutoDisable.Send(Value);
end;

procedure TRigidBodyCollectionNode.SetBodies(const Value: array of TRigidBodyNode);
var
  L: Integer;
  A: array of TX3DNode;
begin
  L := High(Value) + 1;
  SetLength(A, L);
  if L > 0 then
    Move(Value[0], A[0], L * SizeOf(TRigidBodyNode));
  FdBodies.Send(A);
end;

function TRigidBodyCollectionNode.GetConstantForceMix: Single;
begin
  Result := FdConstantForceMix.Value;
end;

procedure TRigidBodyCollectionNode.SetConstantForceMix(const Value: Single);
begin
  FdConstantForceMix.Send(Value);
end;

function TRigidBodyCollectionNode.GetContactSurfaceThickness: Single;
begin
  Result := FdContactSurfaceThickness.Value;
end;

procedure TRigidBodyCollectionNode.SetContactSurfaceThickness(const Value: Single);
begin
  FdContactSurfaceThickness.Send(Value);
end;

function TRigidBodyCollectionNode.GetDisableAngularSpeed: Single;
begin
  Result := FdDisableAngularSpeed.Value;
end;

procedure TRigidBodyCollectionNode.SetDisableAngularSpeed(const Value: Single);
begin
  FdDisableAngularSpeed.Send(Value);
end;

function TRigidBodyCollectionNode.GetDisableLinearSpeed: Single;
begin
  Result := FdDisableLinearSpeed.Value;
end;

procedure TRigidBodyCollectionNode.SetDisableLinearSpeed(const Value: Single);
begin
  FdDisableLinearSpeed.Send(Value);
end;

function TRigidBodyCollectionNode.GetDisableTime: Single;
begin
  Result := FdDisableTime.Value;
end;

procedure TRigidBodyCollectionNode.SetDisableTime(const Value: Single);
begin
  FdDisableTime.Send(Value);
end;

function TRigidBodyCollectionNode.GetEnabled: boolean;
begin
  Result := FdEnabled.Value;
end;

procedure TRigidBodyCollectionNode.SetEnabled(const Value: boolean);
begin
  FdEnabled.Send(Value);
end;

function TRigidBodyCollectionNode.GetErrorCorrection: Single;
begin
  Result := FdErrorCorrection.Value;
end;

procedure TRigidBodyCollectionNode.SetErrorCorrection(const Value: Single);
begin
  FdErrorCorrection.Send(Value);
end;

function TRigidBodyCollectionNode.GetGravity: TVector3;
begin
  Result := FdGravity.Value;
end;

procedure TRigidBodyCollectionNode.SetGravity(const Value: TVector3);
begin
  FdGravity.Send(Value);
end;

function TRigidBodyCollectionNode.GetIterations: Integer;
begin
  Result := FdIterations.Value;
end;

procedure TRigidBodyCollectionNode.SetIterations(const Value: Integer);
begin
  FdIterations.Send(Value);
end;

procedure TRigidBodyCollectionNode.SetJoints(const Value: array of TAbstractRigidJointNode);
var
  L: Integer;
  A: array of TX3DNode;
begin
  L := High(Value) + 1;
  SetLength(A, L);
  if L > 0 then
    Move(Value[0], A[0], L * SizeOf(TAbstractRigidJointNode));
  FdJoints.Send(A);
end;

function TRigidBodyCollectionNode.GetMaxCorrectionSpeed: Single;
begin
  Result := FdMaxCorrectionSpeed.Value;
end;

procedure TRigidBodyCollectionNode.SetMaxCorrectionSpeed(const Value: Single);
begin
  FdMaxCorrectionSpeed.Send(Value);
end;

function TRigidBodyCollectionNode.GetPreferAccuracy: boolean;
begin
  Result := FdPreferAccuracy.Value;
end;

procedure TRigidBodyCollectionNode.SetPreferAccuracy(const Value: boolean);
begin
  FdPreferAccuracy.Send(Value);
end;

function TRigidBodyCollectionNode.GetCollider: TCollisionCollectionNode;
begin
  if FdCollider.Value is TCollisionCollectionNode then
    Result := TCollisionCollectionNode(FdCollider.Value)
  else
    Result := nil;
end;

procedure TRigidBodyCollectionNode.SetCollider(const Value: TCollisionCollectionNode);
begin
  FdCollider.Send(Value);
end;

{$endif read_implementation}
