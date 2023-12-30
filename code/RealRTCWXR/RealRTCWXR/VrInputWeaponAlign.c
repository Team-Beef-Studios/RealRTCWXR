/************************************************************************************

Filename	:	VrInputWeaponAlign.c
Content		:	Handles default controller input
Created		:	August 2019
Authors		:	Simon Brown

*************************************************************************************/

#include "VrInput.h"
#include "VrCvars.h"

#include "../client/client.h"


void HandleInput_WeaponAlign(ovrInputStateTrackedRemote* pDominantTrackedRemoteNew, ovrInputStateTrackedRemote* pDominantTrackedRemoteOld, ovrTrackedController* pDominantTracking,
    ovrInputStateTrackedRemote* pOffTrackedRemoteNew, ovrInputStateTrackedRemote* pOffTrackedRemoteOld, ovrTrackedController* pOffTracking,
    int domButton1, int domButton2, int offButton1, int offButton2)

{
    //always right handed for this
    vr.right_handed = true;

    static qboolean dominantGripPushed = false;

    //Allow weapon alignment mode toggle on x
    if (vr_align_weapons->value)
    {
        bool offhandX = (pOffTrackedRemoteNew->Buttons & xrButton_X);
        if ((offhandX != ((pOffTrackedRemoteOld->Buttons & xrButton_X) != 0)) && offhandX)
        {
            Cvar_Set("vr_control_scheme", "0");
        }
    }

    //Set controller angles - We need to calculate all those we might need (including adjustments) for the client to then take its pick
    {
        vec3_t rotation = { 0 };
        QuatToYawPitchRoll(pDominantTracking->Pose.orientation, rotation, vr.weaponangles[ANGLES_DEFAULT]);
        QuatToYawPitchRoll(pOffTracking->Pose.orientation, rotation, vr.offhandangles[ANGLES_DEFAULT]);

        rotation[PITCH] = vr_knife_pitchadjust->value;
        //Individual Controller offsets (so that they match quest)
        if (gAppState.controllersPresent == INDEX_CONTROLLERS)
        {
            rotation[PITCH] += 10.938125f;
        }
        else if (gAppState.controllersPresent == VIVE_CONTROLLERS)
        {
            rotation[PITCH] += 13.6725f;
        }
        else if (gAppState.controllersPresent == PICO_CONTROLLERS)
        {
            rotation[PITCH] += 12.500625f;
        }
        QuatToYawPitchRoll(pDominantTracking->GripPose.orientation, rotation, vr.weaponangles[ANGLES_KNIFE]);
        QuatToYawPitchRoll(pOffTracking->GripPose.orientation, rotation, vr.offhandangles[ANGLES_KNIFE]);

        //VIVE CONTROLLERS -> -33.6718750
        rotation[PITCH] = vr_weapon_pitchadjust->value;
        if (gAppState.controllersPresent == VIVE_CONTROLLERS)
        {
            rotation[PITCH] -= 33.6718750f;
        }
        QuatToYawPitchRoll(pDominantTracking->Pose.orientation, rotation, vr.weaponangles[ANGLES_ADJUSTED]);
        QuatToYawPitchRoll(pOffTracking->Pose.orientation, rotation, vr.offhandangles[ANGLES_ADJUSTED]);

        for (int anglesIndex = 0; anglesIndex <= ANGLES_KNIFE; ++anglesIndex)
        {
            VectorSubtract(vr.weaponangles_last[anglesIndex], vr.weaponangles[anglesIndex], vr.weaponangles_delta[anglesIndex]);
            VectorCopy(vr.weaponangles[anglesIndex], vr.weaponangles_last[anglesIndex]);

            VectorSubtract(vr.offhandangles_last[anglesIndex], vr.offhandangles[anglesIndex], vr.offhandangles_delta[anglesIndex]);
            VectorCopy(vr.offhandangles[anglesIndex], vr.offhandangles_last[anglesIndex]);
        }

        //Record recent weapon position for trajectory based stuff
        for (int i = (NUM_WEAPON_SAMPLES - 1); i != 0; --i) {
            VectorCopy(vr.weaponoffset_history[i - 1], vr.weaponoffset_history[i]);
            vr.weaponoffset_history_timestamp[i] = vr.weaponoffset_history_timestamp[i - 1];
        }
        VectorCopy(vr.weaponoffset, vr.weaponoffset_history[0]);
        vr.weaponoffset_history_timestamp[0] = vr.weaponoffset_timestamp;


        VectorSet(vr.weaponposition, pDominantTracking->Pose.position.x,
            pDominantTracking->Pose.position.y, pDominantTracking->Pose.position.z);

        ///Weapon location relative to view
        VectorSet(vr.weaponoffset, pDominantTracking->Pose.position.x,
            pDominantTracking->Pose.position.y, pDominantTracking->Pose.position.z);
        VectorSubtract(vr.weaponoffset, vr.hmdposition, vr.weaponoffset);
        vr.weaponoffset_timestamp = Sys_Milliseconds();


        vec3_t velocity;
        VectorSet(velocity, pDominantTracking->Velocity.linearVelocity.x,
            pDominantTracking->Velocity.linearVelocity.y, pDominantTracking->Velocity.linearVelocity.z);
        vr.primaryswingvelocity = VectorLength(velocity);

        VectorSet(velocity, pOffTracking->Velocity.linearVelocity.x,
            pOffTracking->Velocity.linearVelocity.y, pOffTracking->Velocity.linearVelocity.z);
        vr.secondaryswingvelocity = VectorLength(velocity);
    }

    //Menu button
    handleTrackedControllerButton(&leftTrackedRemoteState_new, &leftTrackedRemoteState_old, xrButton_Enter, K_ESCAPE);

    static float menuYaw = 0;

    static qboolean resetCursor = qtrue;
    if (VR_UseScreenLayer())
    {
        bool controlsLeftHanded = vr_control_scheme->integer >= 10;
        if (controlsLeftHanded == vr.menu_right_handed) {
            interactWithTouchScreen(menuYaw, vr.offhandangles[ANGLES_DEFAULT]);
            handleTrackedControllerButton(pOffTrackedRemoteNew, pOffTrackedRemoteOld, offButton1, K_MOUSE1);
            handleTrackedControllerButton(pOffTrackedRemoteNew, pOffTrackedRemoteOld, xrButton_Trigger, K_MOUSE1);
            handleTrackedControllerButton(pOffTrackedRemoteNew, pOffTrackedRemoteOld, offButton2, K_ESCAPE);
            if ((pDominantTrackedRemoteNew->Buttons & xrButton_Trigger) != (pDominantTrackedRemoteOld->Buttons & xrButton_Trigger) && (pDominantTrackedRemoteNew->Buttons & xrButton_Trigger)) {
                vr.menu_right_handed = !vr.menu_right_handed;
            }
        }
        else {
            interactWithTouchScreen(menuYaw, vr.weaponangles[ANGLES_DEFAULT]);
            handleTrackedControllerButton(pDominantTrackedRemoteNew, pDominantTrackedRemoteOld, domButton1, K_MOUSE1);
            handleTrackedControllerButton(pDominantTrackedRemoteNew, pDominantTrackedRemoteOld, xrButton_Trigger, K_MOUSE1);
            handleTrackedControllerButton(pDominantTrackedRemoteNew, pDominantTrackedRemoteOld, domButton2, K_ESCAPE);
            if ((pOffTrackedRemoteNew->Buttons & xrButton_Trigger) != (pOffTrackedRemoteOld->Buttons & xrButton_Trigger) && (pOffTrackedRemoteNew->Buttons & xrButton_Trigger)) {
                vr.menu_right_handed = !vr.menu_right_handed;
            }
        }
    }
    else
    {
        resetCursor = qtrue;

        //This section corrects for the fact that the controller actually controls direction of movement, but we want to move relative to the direction the
        //player is facing for positional tracking
        vec2_t v;
        rotateAboutOrigin(-vr.hmdposition_delta[0] * vr_positional_factor->value,
            vr.hmdposition_delta[2] * vr_positional_factor->value, -vr.hmdorientation[YAW], v);
        positional_movementSideways = v[0];
        positional_movementForward = v[1];

        dominantGripPushed = (pDominantTrackedRemoteNew->Buttons &
            xrButton_GripTrigger) != 0;

        //We need to record if we have started firing primary so that releasing trigger will stop firing, if user has pushed grip
        //in meantime, then it wouldn't stop the gun firing and it would get stuck
        if (dominantGripPushed)
        {
            //Fire Secondary
            if (((pDominantTrackedRemoteNew->Buttons & xrButton_Trigger) !=
                (pDominantTrackedRemoteOld->Buttons & xrButton_Trigger))
                && (pDominantTrackedRemoteNew->Buttons & xrButton_Trigger))
            {
                sendButtonActionSimple("weapalt");
            }
        }
        else
        {
            //Fire Primary
            if (!vr.velocitytriggered && // Don't fire velocity triggered weapons
                (pDominantTrackedRemoteNew->Buttons & xrButton_Trigger) !=
                (pDominantTrackedRemoteOld->Buttons & xrButton_Trigger)) {

                sendButtonAction("+attack", (pDominantTrackedRemoteNew->Buttons & xrButton_Trigger));
            }
        }

        //Next Weapon with A
        if (((pDominantTrackedRemoteNew->Buttons & domButton1) !=
            (pDominantTrackedRemoteOld->Buttons & domButton1)) &&
            (pDominantTrackedRemoteOld->Buttons & domButton1)) {
            sendButtonActionSimple("weapnext");
        }

        //Prev Weapon with B
        if (((pDominantTrackedRemoteNew->Buttons & domButton2) !=
            (pDominantTrackedRemoteOld->Buttons & domButton2)) &&
            (pDominantTrackedRemoteOld->Buttons & domButton2)) {
            sendButtonActionSimple("weapprev");
        }

        static int item_index = 0;
        float* items[7] = { &vr.test_scale, &(vr.test_offset[0]), &(vr.test_offset[1]), &(vr.test_offset[2]),
                           &(vr.test_angles[PITCH]), &(vr.test_angles[YAW]), &(vr.test_angles[ROLL]) };
        char* item_names[7] = { "scale", "right", "up", "forward", "pitch", "yaw", "roll" };
        float  item_inc[7] = { 0.002, 0.02, 0.02, 0.02, 0.1, 0.1, 0.1 };

        //Weapon/Inventory Chooser
        static qboolean itemSwitched = false;
        if (between(-0.2f, pDominantTrackedRemoteNew->Joystick.y, 0.2f) &&
            (between(0.8f, pDominantTrackedRemoteNew->Joystick.x, 1.0f) ||
                between(-1.0f, pDominantTrackedRemoteNew->Joystick.x, -0.8f)))
        {
            if (!itemSwitched) {
                if (between(0.8f, pDominantTrackedRemoteNew->Joystick.x, 1.0f))
                {
                    item_index++;
                    if (item_index == 7)
                        item_index = 0;
                }
                else
                {
                    item_index--;
                    if (item_index < 0)
                        item_index = 6;
                }
                itemSwitched = true;
            }
        }
        else {
            itemSwitched = false;
        }

        if (((pDominantTrackedRemoteNew->Buttons & xrButton_Joystick) !=
            (pDominantTrackedRemoteOld->Buttons & xrButton_Joystick)) &&
            (pDominantTrackedRemoteOld->Buttons & xrButton_Joystick))
        {
            *(items[item_index]) = 0.0;
        }

        //Left-hand specific stuff
        {
            if (((pOffTrackedRemoteNew->Buttons & offButton1) !=
                (pOffTrackedRemoteOld->Buttons & offButton1)) &&
                (pOffTrackedRemoteOld->Buttons & offButton1)) {
                //If cheats enabled, give all weapons/pickups to player
                Cbuf_AddText("give all\n");
            }


            if (between(-0.2f, pDominantTrackedRemoteNew->Joystick.x, 0.2f))
            {
                if (pDominantTrackedRemoteNew->Joystick.y > 0.6f) {
                    *(items[item_index]) += item_inc[item_index];
                }

                if (pDominantTrackedRemoteNew->Joystick.y < -0.6f) {
                    *(items[item_index]) -= item_inc[item_index];
                }
            }
        }

        Com_sprintf(vr.test_name, sizeof(vr.test_name), "ID: %i, %s: %.3f", cl.snap.ps.weapon, item_names[item_index], *(items[item_index]));

        char cvar_name[64];
        char* cvar_pattern = vr_align_weapons->value == 1 ? "vr_weapon_adjustment_%i" : "vr_weapon_hand_adjustment_%i";
        Com_sprintf(cvar_name, sizeof(cvar_name), cvar_pattern, cl.snap.ps.weapon);

        char buffer[256];
        Com_sprintf(buffer, sizeof(buffer), "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f", vr.test_scale, (vr.test_offset[0] / vr.test_scale), (vr.test_offset[1] / vr.test_scale), (vr.test_offset[2] / vr.test_scale),
            (vr.test_angles[PITCH]), (vr.test_angles[YAW]), (vr.test_angles[ROLL]));
        Cvar_Set(cvar_name, buffer);
    }



    //Save state
    rightTrackedRemoteState_old = rightTrackedRemoteState_new;
    leftTrackedRemoteState_old = leftTrackedRemoteState_new;
}