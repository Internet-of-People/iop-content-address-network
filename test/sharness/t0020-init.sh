#!/bin/sh
#
# Copyright (c) 2014 Christian Couder
# MIT Licensed; see the LICENSE file in this repository.
#

test_description="Test init command"

. lib/test-lib.sh

# test that ipfs fails to init if IOPCAN_PATH isnt writeable
test_expect_success "create dir and change perms succeeds" '
	export IOPCAN_PATH="$(pwd)/.badipfs" &&
	mkdir "$IOPCAN_PATH" &&
	chmod 000 "$IOPCAN_PATH"
'

test_expect_success "ipfs init fails" '
	test_must_fail ipfs init 2> init_fail_out
'

# Under Windows/Cygwin the error message is different,
# so we use the STD_ERR_MSG prereq.
if test_have_prereq STD_ERR_MSG; then
	init_err_msg="Error: failed to take lock at $IOPCAN_PATH: permission denied"
else
	init_err_msg="Error: mkdir $IOPCAN_PATH: The system cannot find the path specified."
fi

test_expect_success "ipfs init output looks good" '
	echo "$init_err_msg" >init_fail_exp &&
	test_cmp init_fail_exp init_fail_out
'

test_expect_success "cleanup dir with bad perms" '
	chmod 775 "$IOPCAN_PATH" &&
	rmdir "$IOPCAN_PATH"
'

# test no repo error message
# this applies to `ipfs add sth`, `ipfs refs <hash>`
test_expect_success "ipfs cat fails" '
    export IOPCAN_PATH="$(pwd)/.iopcan" &&
    test_must_fail ipfs cat Qmaa4Rw81a3a1VEx4LxB7HADUAXvZFhCoRdBzsMZyZmqHD 2> cat_fail_out
'

test_expect_success "ipfs cat no repo message looks good" '
    echo "Error: no IPFS repo found in $IOPCAN_PATH." > cat_fail_exp &&
    echo "please run: 'ipfs init'" >> cat_fail_exp &&
    test_path_cmp cat_fail_exp cat_fail_out
'

# test that init succeeds
test_expect_success "ipfs init succeeds" '
	export IOPCAN_PATH="$(pwd)/.iopcan" &&
	echo "IOPCAN_PATH: \"$IOPCAN_PATH\"" &&
	BITS="2048" &&
	ipfs init --bits="$BITS" >actual_init ||
	test_fsh cat actual_init
'

test_expect_success ".iopcan/ has been created" '
	test -d ".iopcan" &&
	test -f ".iopcan/config" &&
	test -d ".iopcan/datastore" &&
	test -d ".iopcan/blocks" ||
	test_fsh ls -al .iopcan
'

test_expect_success "ipfs config succeeds" '
	echo /ipfs >expected_config &&
	ipfs config Mounts.IPFS >actual_config &&
	test_cmp expected_config actual_config
'

test_expect_success "ipfs peer id looks good" '
	PEERID=$(ipfs config Identity.PeerID) &&
	test_check_peerid "$PEERID"
'

test_expect_success "ipfs init output looks good" '
	STARTFILE="ipfs cat /ipfs/$HASH_WELCOME_DOCS/readme" &&
	echo "initializing IPFS node at $IOPCAN_PATH" >expected &&
	echo "generating $BITS-bit RSA keypair...done" >>expected &&
	echo "peer identity: $PEERID" >>expected &&
	echo "to get started, enter:" >>expected &&
	printf "\\n\\t$STARTFILE\\n\\n" >>expected &&
	test_cmp expected actual_init
'

test_expect_success "Welcome readme exists" '
	ipfs cat /ipfs/$HASH_WELCOME_DOCS/readme
'

test_expect_success "clean up ipfs dir" '
	rm -rf "$IOPCAN_PATH"
'

test_expect_success "'ipfs init --empty-repo' succeeds" '
	BITS="1024" &&
	ipfs init --bits="$BITS" --empty-repo >actual_init
'

test_expect_success "ipfs peer id looks good" '
	PEERID=$(ipfs config Identity.PeerID) &&
	test_check_peerid "$PEERID"
'

test_expect_success "'ipfs init --empty-repo' output looks good" '
	echo "initializing IPFS node at $IOPCAN_PATH" >expected &&
	echo "generating $BITS-bit RSA keypair...done" >>expected &&
	echo "peer identity: $PEERID" >>expected &&
	test_cmp expected actual_init
'

test_expect_success "Welcome readme doesn't exists" '
	test_must_fail ipfs cat /ipfs/$HASH_WELCOME_DOCS/readme
'

test_expect_success "clean up ipfs dir" '
	rm -rf "$IOPCAN_PATH"
'

test_init_ipfs

test_launch_ipfs_daemon

test_expect_success "ipfs init should not run while daemon is running" '
	test_must_fail ipfs init 2> daemon_running_err &&
	EXPECT="Error: ipfs daemon is running. please stop it to run this command" &&
	grep "$EXPECT" daemon_running_err
'

test_kill_ipfs_daemon

test_done
