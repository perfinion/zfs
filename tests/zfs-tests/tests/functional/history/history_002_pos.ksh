#!/bin/ksh -p
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright 2009 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.

#
# Copyright (c) 2013 by Delphix. All rights reserved.
#

. $STF_SUITE/tests/functional/history/history_common.kshlib

#
# DESCRIPTION:
#	Create a  scenario to verify the following zfs subcommands are logged.
#	create, destroy, clone, rename, snapshot, rollback, set, inherit,
#	receive, promote, hold and release.
#
# STRATEGY:
#	1. Verify that all the zfs commands listed (barring send) produce an
#	   entry in the pool history.
#

verify_runnable "global"

function cleanup
{

	[[ -f $tmpfile ]] && $RM -f $tmpfile
	[[ -f $tmpfile2 ]] && $RM -f $tmpfile2
	for dataset in $fs $newfs $fsclone $vol $newvol $volclone; do
		datasetexists $dataset && $ZFS destroy -Rf $dataset
	done
	$RM -rf /history.$$
}

log_assert "Verify zfs sub-commands which modify state are logged."
log_onexit cleanup

fs=$TESTPOOL/$TESTFS1; newfs=$TESTPOOL/newfs; fsclone=$TESTPOOL/clone
vol=$TESTPOOL/$TESTVOL ; newvol=$TESTPOOL/newvol; volclone=$TESTPOOL/volclone
fssnap=$fs@fssnap; fssnap2=$fs@fssnap2
volsnap=$vol@volsnap; volsnap2=$vol@volsnap2
tmpfile=/tmp/tmpfile.$$ ; tmpfile2=/tmp/tmpfile2.$$

if is_linux; then
#	property	value		property	value
#
props=(
	quota		64M		recordsize	512
	reservation	32M		reservation	none
	mountpoint	/history.$$	mountpoint	legacy
	mountpoint	none		compression	lz4
	compression	on		compression	off
	compression	lzjb		acltype		noacl
	acltype		posixacl	xattr		sa
	atime		on		atime		off
	devices		on		devices		off
	exec		on		exec		off
	setuid		on		setuid		off
	readonly	on		readonly	off
	zoned		on		zoned		off
	snapdir		hidden		snapdir		visible
	aclinherit	discard		aclinherit	noallow
	aclinherit	secure		aclinherit	passthrough
	canmount	off		canmount	on
	xattr		on		xattr		off
	compression	gzip		compression	gzip-$((RANDOM%9 + 1))
	copies		$((RANDOM%3 + 1))
)
else
#	property	value		property	value
#
props=(
	quota		64M		recordsize	512
	reservation	32M		reservation	none
	mountpoint	/history.$$	mountpoint	legacy
	mountpoint	none		sharenfs	on
	sharenfs	off
	compression	on		compression	off
	compression	lzjb		aclmode		discard
	aclmode		groupmask	aclmode		passthrough
	atime		on		atime		off
	devices		on		devices		off
	exec		on		exec		off
	setuid		on		setuid		off
	readonly	on		readonly	off
	zoned		on		zoned		off
	snapdir		hidden		snapdir		visible
	aclinherit	discard		aclinherit	noallow
	aclinherit	secure		aclinherit	passthrough
	canmount	off		canmount	on
	xattr		on		xattr		off
	compression	gzip		compression	gzip-$((RANDOM%9 + 1))
	copies		$((RANDOM%3 + 1))
)
fi

run_and_verify "$ZFS create $fs"
# Set all the property for filesystem
typeset -i i=0
while ((i < ${#props[@]})) ; do
	run_and_verify "$ZFS set ${props[$i]}=${props[((i+1))]} $fs"

	# quota, reservation, canmount can not be inherited.
	#
	if [[ ${props[$i]} != "quota" && ${props[$i]} != "reservation" && \
	    ${props[$i]} != "canmount" ]];
	then
		run_and_verify "$ZFS inherit ${props[$i]} $fs"
	fi

	((i += 2))
done

run_and_verify "$ZFS create -V 64M $vol"
run_and_verify "$ZFS set volsize=32M $vol"
run_and_verify "$ZFS snapshot $fssnap"
run_and_verify "$ZFS hold tag $fssnap"
run_and_verify "$ZFS release tag $fssnap"
run_and_verify "$ZFS snapshot $volsnap"
run_and_verify "$ZFS snapshot $fssnap2"
run_and_verify "$ZFS snapshot $volsnap2"

# Send isn't logged...
log_must $ZFS send -i $fssnap $fssnap2 > $tmpfile
log_must $ZFS send -i $volsnap $volsnap2 > $tmpfile2
# Verify that's true
$ZPOOL history $TESTPOOL | $GREP 'zfs send' >/dev/null 2>&1 && \
    log_fail "'zfs send' found in history of \"$TESTPOOL\""

run_and_verify "$ZFS destroy $fssnap2"
run_and_verify "$ZFS destroy $volsnap2"
run_and_verify "$ZFS receive $fs < $tmpfile"
run_and_verify "$ZFS receive $vol < $tmpfile2"
run_and_verify "$ZFS rollback -r $fssnap"
run_and_verify "$ZFS rollback -r $volsnap"
run_and_verify "$ZFS clone $fssnap $fsclone"
run_and_verify "$ZFS clone $volsnap $volclone"
run_and_verify "$ZFS rename $fs $newfs"
run_and_verify "$ZFS rename $vol $newvol"
run_and_verify "$ZFS promote $fsclone"
run_and_verify "$ZFS promote $volclone"
run_and_verify "$ZFS destroy $newfs"
run_and_verify "$ZFS destroy $newvol"
run_and_verify "$ZFS destroy -rf $fsclone"
run_and_verify "$ZFS destroy -rf $volclone"

log_pass "zfs sub-commands which modify state are logged passed."
