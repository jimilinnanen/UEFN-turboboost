using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Vehicles }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Verse.org/SpatialMath }
using { /Verse.org/Verse }

# Multiplayer-safe vehicle thruster using a pool of pre-placed air vents.
Vehicle_Turbo_Device := class(creative_device):

    # --- @editable Devices (must be configured in UEFN editor) ---

    @editable
    BoostTrigger : trigger_device = trigger_device{}

    # MODIFIED: Changed from button_device to trigger_device
    @editable
    UpgradeTrigger : trigger_device = trigger_device{}

    # POOL: Assign ALL pre-placed air vents here in the editor.
    # The number of vents should match your max expected concurrent boosters.
    @editable
    VentPool : []air_vent_device = array{}

    @editable
    SpeedDisplay : hud_message_device = hud_message_device{}

    # --- @editable Configuration ---

    @editable
    VentOffset : float = 200.0

    @editable
    UpwardPitchDegrees : float = 90.0

    @editable
    BaseYawDegrees : float = 90.0

    # --- State Tracking (for multiplayer) ---

    # Tracks which players have purchased the boost upgrade.
    var PlayerUpgrades : [agent]logic = map{}

    # Queue of vents that are not currently in use.
    var AvailableVents : []air_vent_device = array{}

    # Maps each active boosting player to their assigned vent.
    var ActiveVents : [agent]air_vent_device = map{}

    # --- Lifecycle ---

    OnBegin<override>()<suspends>:void =
        # Initialize the pool with all vents from the editor.
        set AvailableVents = VentPool

        # Ensure all vents start disabled.
        for (Vent : AvailableVents):
            Vent.Disable()

        # Subscribe to all necessary events.
        BoostTrigger.TriggeredEvent.Subscribe(OnBoostTriggered)
        # MODIFIED: Changed from InteractedWithEvent to TriggeredEvent
        UpgradeTrigger.TriggeredEvent.Subscribe(OnUpgradePurchased)
        GetPlayspace().PlayerRemovedEvent().Subscribe(OnPlayerRemoved)

    # --- Event Handlers ---

    # MODIFIED: Signature changed to handle ?agent from trigger event.
    # Called when a player enters the upgrade trigger zone.
    OnUpgradePurchased(MaybeAgent : ?agent) : void =
        # Unwrap the optional agent before using it as a map key.
        if (Agent := MaybeAgent?):
            if (set PlayerUpgrades[Agent] = true):
                Print("Boost upgrade purchased!")

    # Called when any player enters the boost trigger zone.
    OnBoostTriggered(MaybeAgent : ?agent) : void =
        if:
            Agent := MaybeAgent?
            PlayerUpgrades[Agent]          # Guard: player must have upgrade
            not ActiveVents[Agent]         # Guard: player not already boosting
            AvailableVents.Length > 0      # Guard: a vent must be available
            Vent := AvailableVents[0]      # Get the first available vent
        then:
            # Remove the vent from the available pool.
            if (NewAvailable := AvailableVents.RemoveElement[0]):
                set AvailableVents = NewAvailable

            # Assign the vent to this player.
            if (set ActiveVents[Agent] = Vent):
                Print("Thruster activated for player!")
                Vent.Enable()
                spawn { MoveVentLoop(Agent, Vent) }
                spawn { DisplaySpeedLoop(Agent) }

    # Called when a player leaves the game.
    OnPlayerRemoved(InPlayer : player) : void =
        # If the leaving player had an active vent, release it.
        if (Vent := ActiveVents[InPlayer]):
            ReleaseVent(InPlayer, Vent)

    # --- Core Logic ---

    # Continuously teleports a specific vent to follow a specific player's vehicle.
    MoveVentLoop(Agent : agent, Vent : air_vent_device)<suspends> : void =
        loop:
            if:
                Character := Agent.GetFortCharacter[]
                Vehicle := Character.GetVehicle[]
            then:
                # Get vehicle transform (XYZ coordinates).
                VehicleTransform := Vehicle.GetTransform()
                VehiclePos := VehicleTransform.Translation
                VehicleRot := VehicleTransform.Rotation
                ForwardDir := VehicleRot.GetLocalForward()

                # Calculate target position behind the car.
                TargetPos := (/UnrealEngine.com/Temporary/SpatialMath:)vector3{
                    X := VehiclePos.X - (ForwardDir.X * VentOffset),
                    Y := VehiclePos.Y - (ForwardDir.Y * VentOffset),
                    Z := VehiclePos.Z - (ForwardDir.Z * VentOffset)
                }

                # Apply yaw to align behind car, then pitch to point upwards.
                YawRadians := (/UnrealEngine.com/Temporary/SpatialMath:)DegreesToRadians(BaseYawDegrees)
                RotWithYaw := VehicleRot.ApplyYaw(YawRadians)
                PitchRadians := (/UnrealEngine.com/Temporary/SpatialMath:)DegreesToRadians(UpwardPitchDegrees)
                TargetRot := RotWithYaw.ApplyPitch(PitchRadians)

                # Teleport the assigned vent.
                if (Vent.TeleportTo[TargetPos, TargetRot]) {}

                # Refresh physics to apply the new direction.
                Vent.Disable()
                Vent.Enable()
            else:
                # Player is no longer in a vehicle, release the vent.
                ReleaseVent(Agent, Vent)
                break

            Sleep(0.0)

    # Returns a vent to the available pool and removes the player's active mapping.
    ReleaseVent(Agent : agent, Vent : air_vent_device) : void =
        Vent.Disable()

        # Add the vent back to the available queue.
        set AvailableVents += array{Vent}

        # Rebuild the active map without this player's entry.
        var NewActiveVents : [agent]air_vent_device = map{}
        for (Key -> Value : ActiveVents, Key <> Agent):
            set NewActiveVents = ConcatenateMaps(NewActiveVents, map{Key => Value})
        set ActiveVents = NewActiveVents

        Print("Vent released back to pool.")

    # Continuously displays speed on the HUD for a specific player.
    DisplaySpeedLoop(Agent : agent)<suspends> : void =
        loop:
            if:
                Character := Agent.GetFortCharacter[]
                Vehicle := Character.GetVehicle[]
            then:
                SpeedKmh := Vehicle.Speed * 3.6
                if (FlooredSpeed := Floor[SpeedKmh]):
                    SpeedDisplay.Show(Agent, SpeedMessage(FlooredSpeed), ?DisplayTime := 0.0)
            else:
                SpeedDisplay.Hide(Agent)
                break
            Sleep(0.2)

    SpeedMessage<localizes>(Speed : int) : message = "Speed: {Speed} km/h"
