#!/bin/bash

# This script is based on swbd/s5c/local/nnet3/run_tdnn.sh

# this is the standard "tdnn" system, built in nnet3; it's what we use to
# call multi-splice.

# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.
set -e

stage=8
train_stage=247
affix=
common_egs_dir=

# training options
initial_effective_lrate=0.0015
final_effective_lrate=0.00015
num_epochs=10
num_jobs_initial=4
num_jobs_final=4
remove_egs=true

# feature options
use_ivectors=false

# End configuration section.

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

#dir=exp/nnet3/tdnn_sp${affix:+_$affix}
dir=exp/nnet3/tdnn_fbank
gmm_dir=exp/tri5a
#train_set=train_sp
train_set=train	# data/train 
#ali_dir=${gmm_dir}_sp_ali
ali_dir=exp/tri5a_ali
graph_dir=$gmm_dir/graph

#local/nnet3/run_ivector_common.sh --stage $stage || exit 1;

if [ $stage -le 7 ]; then
  echo "$0: creating neural net configs";

  num_targets=$(tree-info $ali_dir/tree |grep num-pdfs|awk '{print $2}')

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  input dim=40 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-2,-1,0,1,2) affine-transform-file=$dir/configs/lda.mat
  # the first splicing is moved before the lda layer, so no splicing here
  #relu-batchnorm-layer name=tdnn1 dim=850
  #relu-batchnorm-layer name=tdnn2 dim=850 input=Append(-1,0,2)
  #relu-batchnorm-layer name=tdnn3 dim=850 input=Append(-3,0,3)
  #relu-batchnorm-layer name=tdnn4 dim=850 input=Append(-7,0,2)
  #relu-batchnorm-layer name=tdnn5 dim=850 input=Append(-3,0,3)
  #relu-batchnorm-layer name=tdnn6 dim=850
  relu-renorm-layer name=tdnn1 dim=850 input=lda
  relu-renorm-layer name=tdnn2 dim=850 input=Append(-1,2)
  relu-renorm-layer name=tdnn3 dim=850 input=Append(-2,1)
  relu-renorm-layer name=tdnn4 dim=850 input=Append(-3,3)
  relu-renorm-layer name=tdnn5 dim=850 input=Append(-2,1)
  relu-renorm-layer name=tdnn6 dim=850
  output-layer name=output input=tdnn6 dim=$num_targets max-change=1.5
EOF
#将 网络配置转换为 nnet3 网络配置文件
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi



if [ $stage -le 8 ]; then
  #if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    #utils/create_split_dir.pl \
     #/export/b0{5,6,7,8}/$USER/kaldi-data/egs/aishell-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  #fi
    steps/nnet3/train_dnn.py --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial $num_jobs_initial \
    --trainer.optimization.num-jobs-final $num_jobs_final \
    --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
    --trainer.optimization.final-effective-lrate $final_effective_lrate \
    --egs.dir "$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --cleanup.preserve-model-interval 500 \
    --use-gpu yes \
    --feat-dir=data/${train_set} \
    --ali-dir $ali_dir \
    --lang data/lang \
    --reporting.email="$reporting_email" \
    --trainer.optimization.minibatch-size 256 \
    --dir=$dir  || exit 1;
fi
:<<EOF

if [ $stage -le 9 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information.
  for decode_set in dev test; do
    num_jobs=`cat data/${decode_set}/utt2spk|cut -d' ' -f2|sort -u|wc -l`	# 说话人个数
    decode_dir=${dir}/decode_$decode_set
    steps/nnet3/decode.sh --nj $num_jobs --cmd "$decode_cmd" \
       $graph_dir data/${decode_set} $decode_dir || exit 1;
       #--online-ivector-dir exp/nnet3/ivectors_${decode_set} \
       #$graph_dir data/${decode_set} $decode_dir || exit 1;
  done
fi
EOF
wait;
exit 0;
