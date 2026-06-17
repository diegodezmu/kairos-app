{
	"patcher": {
		"fileversion": 1,
		"appversion": {
			"major": 9,
			"minor": 0,
			"revision": 10,
			"architecture": "x64",
			"modernui": 1
		},
		"classnamespace": "box",
		"rect": [
			303.0,
			140.0,
			880.0,
			620.0
		],
		"openinpresentation": 1,
		"gridsize": [
			15.0,
			15.0
		],
		"boxes": [
			{
				"box": {
					"id": "comment-title",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						-195.0,
						25.0,
						420.0,
						20.0
					],
					"presentation": 1,
					"presentation_rect": [
						15.0,
						12.0,
						360.0,
						20.0
					],
					"text": "KAIROS Level Sender - place in a Max for Live Audio Effect"
				}
			},
			{
				"box": {
					"id": "comment-setup",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						-195.0,
						53.0,
						620.0,
						20.0
					],
					"presentation": 1,
					"presentation_rect": [
						15.0,
						34.0,
						620.0,
						20.0
					],
					"text": "Target defaults to 127.0.0.1:51515. Give each device a unique source number."
				}
			},
			{
				"box": {
					"id": "in-l",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						"signal"
					],
					"patching_rect": [
						-195.0,
						115.0,
						58.0,
						22.0
					],
					"text": "plugin~ 1"
				}
			},
			{
				"box": {
					"id": "in-r",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						"signal"
					],
					"patching_rect": [
						-95.0,
						115.0,
						58.0,
						22.0
					],
					"text": "plugin~ 2"
				}
			},
			{
				"box": {
					"id": "out-l",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						"signal"
					],
					"patching_rect": [
						-195.0,
						505.0,
						65.0,
						22.0
					],
					"text": "plugout~ 1"
				}
			},
			{
				"box": {
					"id": "out-r",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						"signal"
					],
					"patching_rect": [
						-95.0,
						505.0,
						65.0,
						22.0
					],
					"text": "plugout~ 2"
				}
			},
			{
				"box": {
					"id": "rms-l",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						"signal"
					],
					"patching_rect": [
						25.0,
						115.0,
						112.0,
						22.0
					],
					"text": "average~ 1024 rms"
				}
			},
			{
				"box": {
					"id": "rms-r",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						"signal"
					],
					"patching_rect": [
						165.0,
						115.0,
						112.0,
						22.0
					],
					"text": "average~ 1024 rms"
				}
			},
			{
				"box": {
					"id": "snapshot-l",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"outlettype": [
						"float"
					],
					"patching_rect": [
						25.0,
						160.0,
						82.0,
						22.0
					],
					"text": "snapshot~ 33"
				}
			},
			{
				"box": {
					"id": "snapshot-r",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"outlettype": [
						"float"
					],
					"patching_rect": [
						165.0,
						160.0,
						82.0,
						22.0
					],
					"text": "snapshot~ 33"
				}
			},
			{
				"box": {
					"id": "peak-l",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"outlettype": [
						"float"
					],
					"patching_rect": [
						305.0,
						115.0,
						82.0,
						22.0
					],
					"text": "peakamp~ 33"
				}
			},
			{
				"box": {
					"id": "peak-r",
					"maxclass": "newobj",
					"numinlets": 2,
					"numoutlets": 1,
					"outlettype": [
						"float"
					],
					"patching_rect": [
						425.0,
						115.0,
						82.0,
						22.0
					],
					"text": "peakamp~ 33"
				}
			},
			{
				"box": {
					"id": "pak-levels",
					"maxclass": "newobj",
					"numinlets": 4,
					"numoutlets": 1,
					"outlettype": [
						""
					],
					"patching_rect": [
						165.0,
						225.0,
						120.0,
						22.0
					],
					"text": "pak 0. 0. 0. 0."
				}
			},
			{
				"box": {
					"id": "source-number",
					"maxclass": "live.numbox",
					"numinlets": 1,
					"numoutlets": 2,
					"outlettype": [
						"",
						"float"
					],
					"parameter_enable": 1,
					"patching_rect": [
						-195.0,
						205.0,
						70.0,
						15.0
					],
					"presentation": 1,
					"presentation_rect": [
						15.0,
						72.0,
						70.0,
						20.0
					],
					"saved_attribute_attributes": {
						"valueof": {
							"parameter_longname": "Source",
							"parameter_mmax": 128.0,
							"parameter_mmin": 1.0,
							"parameter_modmode": 0,
							"parameter_shortname": "Source",
							"parameter_type": 1,
							"parameter_unitstyle": 0
						}
					},
					"varname": "live.numbox"
				}
			},
			{
				"box": {
					"id": "source-comment",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						-117.0,
						205.0,
						90.0,
						20.0
					],
					"presentation": 1,
					"presentation_rect": [
						94.0,
						72.0,
						90.0,
						20.0
					],
					"text": "source 1+"
				}
			},
			{
				"box": {
					"id": "enabled-toggle",
					"maxclass": "live.toggle",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						""
					],
					"parameter_enable": 1,
					"patching_rect": [
						-195.0,
						245.0,
						24.0,
						24.0
					],
					"presentation": 1,
					"presentation_rect": [
						15.0,
						108.0,
						24.0,
						24.0
					],
					"saved_attribute_attributes": {
						"valueof": {
							"parameter_enum": [
								"off",
								"on"
							],
							"parameter_longname": "Enabled",
							"parameter_mmax": 1,
							"parameter_modmode": 0,
							"parameter_shortname": "Enabled",
							"parameter_type": 2
						}
					},
					"varname": "live.toggle"
				}
			},
			{
				"box": {
					"id": "enabled-comment",
					"maxclass": "comment",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						-161.0,
						245.0,
						80.0,
						20.0
					],
					"presentation": 1,
					"presentation_rect": [
						48.0,
						110.0,
						80.0,
						20.0
					],
					"text": "enabled"
				}
			},
			{
				"box": {
					"id": "source-message",
					"maxclass": "message",
					"numinlets": 2,
					"numoutlets": 1,
					"outlettype": [
						""
					],
					"patching_rect": [
						-195.0,
						295.0,
						120.0,
						22.0
					],
					"presentation": 1,
					"presentation_rect": [
						15.0,
						145.0,
						150.0,
						22.0
					],
					"text": "source Track"
				}
			},
			{
				"box": {
					"id": "udp-send",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 2,
					"patching_rect": [
						165.0,
						345.0,
						320.0,
						22.0
					],
					"presentation": 1,
					"presentation_rect": [
						185.0,
						145.0,
						280.0,
						22.0
					],
					"text": "node.script kairos_level_node.js @autostart 1",
					"outlettype": [
						"",
						""
					],
					"saved_object_attributes": {
						"filename": "kairos_level_node.js",
						"parameter_enable": 0
					}
				}
			},
			{
				"box": {
					"id": "js-sender",
					"maxclass": "newobj",
					"numinlets": 4,
					"numoutlets": 2,
					"outlettype": [
						"",
						""
					],
					"patching_rect": [
						165.0,
						290.0,
						150.0,
						22.0
					],
					"saved_object_attributes": {
						"filename": "kairos_level_sender.js",
						"parameter_enable": 0
					},
					"text": "js kairos_level_sender.js"
				}
			},
			{
				"box": {
					"id": "print-errors",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 0,
					"patching_rect": [
						355.0,
						345.0,
						140.0,
						22.0
					],
					"text": "print KairosLevel"
				}
			},
			{
				"box": {
					"id": "load-source-number",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						""
					],
					"patching_rect": [
						-195.0,
						170.0,
						70.0,
						22.0
					],
					"text": "loadmess 1"
				}
			},
			{
				"box": {
					"id": "load-enabled",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						""
					],
					"patching_rect": [
						-195.0,
						275.0,
						70.0,
						22.0
					],
					"text": "loadmess 1"
				}
			},
			{
				"box": {
					"id": "load-source-name",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						""
					],
					"patching_rect": [
						-55.0,
						275.0,
						120.0,
						22.0
					],
					"text": "loadmess source Track"
				}
			},
			{
				"box": {
					"id": "load-target",
					"maxclass": "newobj",
					"numinlets": 1,
					"numoutlets": 1,
					"outlettype": [
						""
					],
					"patching_rect": [
						165.0,
						318.0,
						220.0,
						22.0
					],
					"text": "loadmess target 127.0.0.1 51515"
				}
			}
		],
		"lines": [
			{
				"patchline": {
					"destination": [
						"js-sender",
						3
					],
					"source": [
						"enabled-toggle",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"out-l",
						0
					],
					"order": 2,
					"source": [
						"in-l",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"peak-l",
						0
					],
					"order": 0,
					"source": [
						"in-l",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"rms-l",
						0
					],
					"order": 1,
					"source": [
						"in-l",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"out-r",
						0
					],
					"order": 2,
					"source": [
						"in-r",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"peak-r",
						0
					],
					"order": 0,
					"source": [
						"in-r",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"rms-r",
						0
					],
					"order": 1,
					"source": [
						"in-r",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"print-errors",
						0
					],
					"source": [
						"js-sender",
						1
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"udp-send",
						0
					],
					"source": [
						"js-sender",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"enabled-toggle",
						0
					],
					"source": [
						"load-enabled",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"source-number",
						0
					],
					"source": [
						"load-source-number",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"js-sender",
						2
					],
					"source": [
						"load-source-name",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"js-sender",
						0
					],
					"source": [
						"pak-levels",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"pak-levels",
						2
					],
					"source": [
						"peak-l",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"pak-levels",
						3
					],
					"source": [
						"peak-r",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"snapshot-l",
						0
					],
					"source": [
						"rms-l",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"snapshot-r",
						0
					],
					"source": [
						"rms-r",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"js-sender",
						1
					],
					"source": [
						"source-number",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"pak-levels",
						0
					],
					"source": [
						"snapshot-l",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"pak-levels",
						1
					],
					"source": [
						"snapshot-r",
						0
					]
				}
			},
			{
				"patchline": {
					"destination": [
						"js-sender",
						2
					],
					"source": [
						"source-message",
						0
					]
				}
			},
			{
				"patchline": {
					"source": [
						"load-target",
						0
					],
					"destination": [
						"udp-send",
						0
					]
				}
			}
		],
		"parameters": {
			"enabled-toggle": [
				"Enabled",
				"Enabled",
				0
			],
			"source-number": [
				"Source",
				"Source",
				0
			],
			"inherited_shortname": 1
		},
		"dependency_cache": [
			{
				"name": "kairos_level_sender.js",
				"patcherrelativepath": ".",
				"type": "TEXT",
				"implicit": 1
			},
			{
				"name": "kairos_level_node.js",
				"patcherrelativepath": ".",
				"type": "TEXT",
				"implicit": 1
			}
		],
		"project": {
			"name": "KairosLevel",
			"version": 1,
			"viewrect": [
				0.0,
				0.0,
				300.0,
				500.0
			],
			"autoorganize": 1,
			"hideprojectwindow": 1,
			"showdependencies": 1,
			"autolocalize": 0,
			"contents": {
				"patchers": {},
				"code": {
					"kairos_level_sender.js": {
						"kind": "javascript",
						"filename": "kairos_level_sender.js"
					},
					"kairos_level_node.js": {
						"kind": "javascript",
						"filename": "kairos_level_node.js"
					}
				}
			},
			"layout": {},
			"searchpath": {},
			"detailsvisible": 0,
			"amxdtype": 1633771873,
			"readonly": 0,
			"devpathtype": 0,
			"devpath": ".",
			"sortmode": 0,
			"viewmode": 0,
			"includepackages": 0
		},
		"autosave": 0,
		"oscreceiveudpport": 0
	}
}
