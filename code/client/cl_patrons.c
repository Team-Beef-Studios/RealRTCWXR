/*
===========================================================================
cl_patrons.c -- Gold Patron credits, shown briefly when the game exits.

The names live in patrons.txt inside z_zzzRealRTCWXR.pk3, so the list can change
without a code rebuild. The format matches the Elite Force VR and OpenJKDF2 ports.

The engine draws this, not the UI module: "quit" can come from the menu, the
console or a VM, and the UI module is torn down during shutdown. While it is up,
VR_UseScreenLayer() reports the screen layer, so it shows on the virtual screen.
===========================================================================
*/

#include "client.h"
#include <VrInput.h>

#define PATRONS_FILE        "patrons.txt"
#define PATRONS_MAX_GOLD    256
#define PATRONS_MAX_OTHER   8
#define PATRONS_LINE_MAX    64

// Virtual 640x480 layout, which SCR_AdjustFrom640 stretches to the real target
#define PATRONS_SCREEN_W    640
#define PATRONS_SCREEN_H    480
#define PATRONS_MARGIN_TOP  22
#define PATRONS_MARGIN_BOT  14
#define PATRONS_MARGIN_SIDE 16

#define PATRONS_TITLE_SIZE  26
#define PATRONS_FOOTER_SIZE 12
// Name cell size bounds, in 640-space units (a char is size x size)
#define PATRONS_NAME_MAX    20
#define PATRONS_NAME_MIN     7
#define PATRONS_MAX_COLS     4

// The button still held from picking "Quit" would otherwise skip the screen at once
#define PATRONS_GRACE_MS    1200

static char     patrons_title[PATRONS_LINE_MAX];
static char     patrons_gold[PATRONS_MAX_GOLD][PATRONS_LINE_MAX];
static char     patrons_other[PATRONS_MAX_OTHER][PATRONS_LINE_MAX];
static int      patrons_numGold;
static int      patrons_numOther;
static qboolean patrons_loaded;
static qboolean patrons_active;

cvar_t          *cl_patronsTime;

qboolean CL_Patrons_Active( void ) {
	return patrons_active;
}

static void CL_Patrons_Trim( char *s ) {
	int len, i, j;

	len = (int)strlen( s );
	while ( len > 0 && ( s[len-1] == '\r' || s[len-1] == '\n' ||
						 s[len-1] == ' '  || s[len-1] == '\t' ) ) {
		s[--len] = '\0';
	}
	for ( i = 0; s[i] == ' ' || s[i] == '\t'; i++ ) {
		;
	}
	if ( i > 0 ) {
		for ( j = 0; s[i]; ) {
			s[j++] = s[i++];
		}
		s[j] = '\0';
	}
}

/*
===============
CL_Patrons_Init

Parses patrons.txt. Sections are [title], [gold] and [other]; '#' comments and
blank lines are ignored. Without the file the screen is skipped.
===============
*/
void CL_Patrons_Init( void ) {
	union { char *c; void *v; } f;
	int   len;
	char *p, *line;
	int   section = 0;   // 0 none, 1 title, 2 gold, 3 other

	cl_patronsTime = Cvar_Get( "cl_patronsTime", "7", CVAR_ARCHIVE );

	patrons_numGold  = 0;
	patrons_numOther = 0;
	patrons_title[0] = '\0';
	patrons_loaded   = qfalse;

	len = FS_ReadFile( PATRONS_FILE, &f.v );
	if ( !f.c || len <= 0 ) {
		return;
	}

	p = f.c;
	while ( p && *p ) {
		char buf[PATRONS_LINE_MAX];
		char *nl = strchr( p, '\n' );
		int c;

		line = p;
		if ( nl ) {
			*nl = '\0';
			p = nl + 1;
		} else {
			p = NULL;
		}

		Q_strncpyz( buf, line, sizeof( buf ) );
		CL_Patrons_Trim( buf );

		// The console font is ASCII only; a UTF-8 byte would draw as junk glyphs
		for ( c = 0; buf[c]; c++ ) {
			if ( (unsigned char)buf[c] > 126 ) {
				buf[c] = '?';
			}
		}

		if ( !buf[0] || buf[0] == '#' ) {
			continue;
		}

		if ( !Q_stricmp( buf, "[title]" ) ) { section = 1; continue; }
		if ( !Q_stricmp( buf, "[gold]"  ) ) { section = 2; continue; }
		if ( !Q_stricmp( buf, "[other]" ) ) { section = 3; continue; }

		switch ( section ) {
		case 1:
			Q_strncpyz( patrons_title, buf, sizeof( patrons_title ) );
			break;
		case 2:
			if ( patrons_numGold < PATRONS_MAX_GOLD ) {
				Q_strncpyz( patrons_gold[patrons_numGold++], buf, PATRONS_LINE_MAX );
			}
			break;
		case 3:
			if ( patrons_numOther < PATRONS_MAX_OTHER ) {
				Q_strncpyz( patrons_other[patrons_numOther++], buf, PATRONS_LINE_MAX );
			}
			break;
		default:
			break;
		}
	}

	FS_FreeFile( f.v );

	patrons_loaded = (qboolean)( patrons_numGold > 0 || patrons_numOther > 0 );
	if ( patrons_loaded ) {
		Com_Printf( "Loaded %d gold patrons from %s\n", patrons_numGold, PATRONS_FILE );
	}
}

static void CL_Patrons_DrawCentred( int y, const char *str, int size, float *color ) {
	int w = (int)strlen( str ) * size;
	int x = ( PATRONS_SCREEN_W - w ) / 2;

	if ( x < 0 ) {
		x = 0;
	}
	SCR_DrawStringExt( x, y, (float)size, str, color, qtrue, qtrue );
}

static int CL_Patrons_LongestGold( void ) {
	int i, longest = 1;

	for ( i = 0; i < patrons_numGold; i++ ) {
		int l = (int)strlen( patrons_gold[i] );
		if ( l > longest ) {
			longest = l;
		}
	}
	return longest;
}

/*
===============
CL_Patrons_Draw

Called from SCR_DrawScreenField while the credits are up. Everything is in
640x480 space through SCR_DrawStringExt. Do not use SCR_DrawSmallStringExt: it
draws at native resolution, which on the VR eye buffer is a tiny clump.

The column count and text size are picked to fill the space, so the list stays
readable as patrons are added.
===============
*/
void CL_Patrons_Draw( void ) {
	static vec4_t gold   = { 1.00f, 0.82f, 0.30f, 1.0f };
	static vec4_t white  = { 1.00f, 1.00f, 1.00f, 1.0f };
	static vec4_t footer = { 0.80f, 0.80f, 0.80f, 1.0f };
	int titleSize = PATRONS_TITLE_SIZE;
	int longest, avail, top, footTop;
	int cols, bestCols, bestSize, size, rows, lineH, colW, i;

	SCR_FillRect( 0, 0, PATRONS_SCREEN_W, PATRONS_SCREEN_H, colorBlack );

	top = PATRONS_MARGIN_TOP;
	if ( patrons_title[0] ) {
		int titleLen = (int)strlen( patrons_title );
		if ( titleLen * titleSize > PATRONS_SCREEN_W - 2 * PATRONS_MARGIN_SIDE ) {
			titleSize = ( PATRONS_SCREEN_W - 2 * PATRONS_MARGIN_SIDE ) / titleLen;
		}
		CL_Patrons_DrawCentred( top, patrons_title, titleSize, white );
		top += titleSize + 18;
	}

	footTop = PATRONS_SCREEN_H - PATRONS_MARGIN_BOT
			  - patrons_numOther * ( PATRONS_FOOTER_SIZE + 2 );

	if ( patrons_numGold > 0 ) {
		avail   = footTop - top - 8;
		longest = CL_Patrons_LongestGold();

		// More columns give taller rows but narrower cells; take the biggest text
		bestCols = 1;
		bestSize = 0;
		for ( cols = 1; cols <= PATRONS_MAX_COLS; cols++ ) {
			int byH, byW;

			rows = ( patrons_numGold + cols - 1 ) / cols;
			byH  = ( avail / rows ) - 2;
			colW = ( PATRONS_SCREEN_W - 2 * PATRONS_MARGIN_SIDE ) / cols;
			byW  = colW / ( longest + 1 );

			size = ( byH < byW ) ? byH : byW;
			if ( size > bestSize ) {
				bestSize = size;
				bestCols = cols;
			}
		}

		size = bestSize;
		if ( size > PATRONS_NAME_MAX ) {
			size = PATRONS_NAME_MAX;
		}
		if ( size < PATRONS_NAME_MIN ) {
			size = PATRONS_NAME_MIN;
		}

		cols  = bestCols;
		rows  = ( patrons_numGold + cols - 1 ) / cols;
		lineH = size + 2;
		colW  = ( PATRONS_SCREEN_W - 2 * PATRONS_MARGIN_SIDE ) / cols;

		top += ( avail - rows * lineH ) / 2;
		if ( top < PATRONS_MARGIN_TOP ) {
			top = PATRONS_MARGIN_TOP;
		}

		for ( i = 0; i < patrons_numGold; i++ ) {
			const char *name = patrons_gold[i];
			int col = i / rows;
			int row = i % rows;
			int w   = (int)strlen( name ) * size;
			int x   = PATRONS_MARGIN_SIDE + col * colW + ( colW - w ) / 2;

			if ( x < 0 ) {
				x = 0;
			}
			SCR_DrawStringExt( x, top + row * lineH, (float)size, name, gold, qtrue, qtrue );
		}
	}

	for ( i = 0; i < patrons_numOther; i++ ) {
		CL_Patrons_DrawCentred( footTop + i * ( PATRONS_FOOTER_SIZE + 2 ),
								patrons_other[i], PATRONS_FOOTER_SIZE, footer );
	}
}

/*
===============
CL_Patrons_ShowAndWait

Runs its own frame loop from Com_Quit_f, before anything is shut down. Returns
when the display time is up, or on a key or controller press after the grace period.
===============
*/
void CL_Patrons_ShowAndWait( void ) {
	int start, elapsed, duration;

	if ( !patrons_loaded || com_dedicated->integer ) {
		return;
	}
	if ( !cls.rendererStarted || !cls.uiStarted ) {
		return;
	}
	if ( !cl_patronsTime ) {
		return;
	}
	duration = cl_patronsTime->integer * 1000;
	if ( duration <= 0 ) {
		return;
	}

	S_StopAllSounds();
	Key_ClearStates();

	patrons_active = qtrue;
	start = Sys_Milliseconds();

	for ( ;; ) {
		elapsed = Sys_Milliseconds() - start;
		if ( elapsed >= duration ) {
			break;
		}

		// Not Com_EventLoop: that would run queued console commands mid-quit
		IN_Frame();

		// Also polls the controllers, through TBXR_FrameSetup
		SCR_UpdateScreen();

		if ( elapsed > PATRONS_GRACE_MS ) {
			if ( anykeydown ) {
				break;
			}
			if ( leftTrackedRemoteState_new.Buttons || rightTrackedRemoteState_new.Buttons ) {
				break;
			}
		}
	}

	patrons_active = qfalse;
}
