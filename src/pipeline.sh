#!/bin/bash

TOPUP=1

for arg in "$@"
do
    case $arg in
        -i|--notopup)
        TOPUP=0
    esac
done


# Set paths for executables
SynB0_DIR=/Users/kshen/Documents/Projects_Ongoing/tvb-ukbb/SynB0-DISCO_dev
export PATH=$PATH:$SynB0_DIR/data_processing:$SynB0_DIR/src
export PATH=$PATH:/Applications/Convert3DGUI.app/Contents/bin/

# Set up freesurfer
export FREESURFER_HOME=/Applications/freesurfer
source $FREESURFER_HOME/SetUpFreeSurfer.sh

# Set up FSL
. /usr/local/fsl/etc/fslconf/fsl.sh
export PATH=$PATH:/usr/local/fsl/bin
export FSLDIR=/usr/local/fsl

# Set up ANTS
export ANTSPATH=/Applications/ANTs/install/bin
export PATH=$PATH:$ANTSPATH:/Applications/ANTS/Scripts

# Set up pytorch
#source /extra/pytorch/bin/activate

# Prepare input
prepare_input.sh INPUTS/b0.nii.gz INPUTS/T1.nii.gz INPUTS/T1_mask.nii.gz $SynB0_DIR/atlases/mni_icbm152_t1_tal_nlin_asym_09c.nii.gz $SynB0_DIR/atlases/mni_icbm152_t1_tal_nlin_asym_09c_2_5.nii.gz OUTPUTS

# Run inference
NUM_FOLDS=5
for i in $(seq 1 $NUM_FOLDS);
  do echo Performing inference on FOLD: "$i"
  python $SynB0_DIR/src/inference.py OUTPUTS/T1_norm_lin_atlas_2_5.nii.gz OUTPUTS/b0_d_lin_atlas_2_5.nii.gz OUTPUTS/b0_u_lin_atlas_2_5_FOLD_"$i".nii.gz $SynB0_DIR/src/train_lin/num_fold_"$i"_total_folds_"$NUM_FOLDS"_seed_1_num_epochs_100_lr_0.0001_betas_\(0.9\,\ 0.999\)_weight_decay_1e-05_num_epoch_*.pth
done

# Take mean
echo Taking ensemble average
fslmerge -t OUTPUTS/b0_u_lin_atlas_2_5_merged.nii.gz OUTPUTS/b0_u_lin_atlas_2_5_FOLD_*.nii.gz
fslmaths OUTPUTS/b0_u_lin_atlas_2_5_merged.nii.gz -Tmean OUTPUTS/b0_u_lin_atlas_2_5.nii.gz

# Apply inverse xform to undistorted b0
echo Applying inverse xform to undistorted b0
antsApplyTransforms -d 3 -i OUTPUTS/b0_u_lin_atlas_2_5.nii.gz -r INPUTS/b0.nii.gz -n BSpline -t [OUTPUTS/epi_reg_d_ANTS.txt,1] -t [OUTPUTS/ANTS0GenericAffine.mat,1] -o OUTPUTS/b0_u.nii.gz

# Smooth image
echo Applying slight smoothing to distorted b0
fslmaths INPUTS/b0.nii.gz -s 1.15 OUTPUTS/b0_d_smooth.nii.gz

if [[ $TOPUP -eq 1 ]]; then
    # Merge results and run through topup
    echo Running topup
    fslmerge -t OUTPUTS/b0_all.nii.gz OUTPUTS/b0_d_smooth.nii.gz OUTPUTS/b0_u.nii.gz
    topup -v --imain=OUTPUTS/b0_all.nii.gz --datain=INPUTS/acqparams.txt --config=b02b0.cnf --iout=OUTPUTS/b0_all_topup.nii.gz --out=OUTPUTS/topup --subsamp=1,1,1,1,1,1,1,1,1 --miter=10,10,10,10,10,20,20,30,30 --lambda=0.00033,0.000067,0.0000067,0.000001,0.00000033,0.000000033,0.0000000033,0.000000000033,0.00000000000067 --scale=0
fi


# Done
echo FINISHED!!!
