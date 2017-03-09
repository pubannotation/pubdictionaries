#!/bin/sh -
script/delayed_job --pool=upload,general --pool=annotation,general:2 --pool=general start