% This is the third version of the Post_HS2_script. 
% This script allows for calculating big spiketimestamps data by cutting
% the data into batches which are processes after another. This prevents
% the memory from overflowing. 

% Marvin @10.08.2018


%% Global variables

clearvars
clc
trigger_rate = 0.001; %in s. %from older version
whole_stimulus = 1
trigger_freq = 0.001 %from older version, probably redundant
%Mode 1 for recordings with one complete stimulus loop, Mode 0 if no
%complete Loop.
Mode = 1;
Batch = 500;

%Memory save for the plotting of the Chirp and other things in future.
memory_save = 1;
%Set want_Kernels to 1 if you want to compute Kernels and/or plot them.
%Should be changed in future so that plotting is dependent on User input
want_Kernels = 1;


% %% Ask for the animal model
% answer = questdlg('Which animal was used', ...
% 	'Animal Model', ...
% 	'Zebrafish', 'Chicken','Zebrafish');
% % Handle response
% switch answer
%     case 'Zebrafish'
%         disp(answer)
%         LEDs_used = 
%     case 'No'
%         disp([answer])
%         Load_choice = 0;
% end
% 

%% Ask for Saved Data

%%%
% This creates a dialog box asking for saved data. If user decides to not
% load saved data the script continues with the post spike sorting
% processing of "new" data.
answer = questdlg('Would you like to load saved Epochs data?', ...
	'Saved Data', ...
	'Yes', 'No','No');
% Handle response
    switch answer
        case 'Yes'
            disp(answer)
            Load_choice = 1;
        case 'No'
            disp([answer])
            Load_choice = 0;
    end

Load_choice = logical(Load_choice);


%Decide wheather to run the analysis code or load the saved data
if Load_choice == 1
    %Load the respective data file
    [Saved_Epoch,Epoch_path] = uigetfile('*.mat','Select stimulus file');
     cd (Epoch_path);
     load(Saved_Epoch);
     disp('Loaded... binsize is = ')
     disp(Epochs.binsize)
     %Extract the data from the Epochs structure
     %Not used at the moment as the data gets extracted on spot at the
     %moment
%      RGB_value = gather(Epochs.RGB_value);
     Smoothened_averaged_spikes = gather(Epochs.Smoothened_averaged_spikes);
%      spiketimestamps = gather(Epochs.spiketimestamps);
%     
    
    
    
else %In case no saved data is loaded
% trigger_rate = (1/30);
% fff_repeat = 30;  %If fff are shown in a row: number of repeats.
% r_repeat = 5000;    % number of repeats of the random noise stimulus

pre_stimulus_window = 1; %Time in seconds that are shown before the stimulus begins
%At the moment the script can only deal with input == 1, but this shall be
%changed in future

%Load the sorted spikes
[hdfname,pathname] = uigetfile('*.hdf5','Select hdf5 file')
% want_spike_trace = 0
HdfFile=strcat(pathname,hdfname);
centres_temp = double(h5read(HdfFile,'/centres'));   % get the cluster localisation
centres_temp = centres_temp';
% columns 1&2 refer to x and y coordinates respectively
cluster_id =double(h5read(HdfFile,'/cluster_id'));  % the cluter id's for every spike
times = double(h5read(HdfFile,'/times'));  % the time ( in data point) 
%for each spike (note cluster_id and times has the same length, becomes important later)
Sampling = double(h5read(HdfFile,'/Sampling')); 
Channels = double(h5read(HdfFile,'/ch')); 
%Shapes = double(h5read(HdfFile,'/shapes')); 
time_in_s = times / Sampling; %Converts the information about frames into time in s

% some things to do before we can strt. Here I generate a big matrix with 
%all spikes - each column stands for a cluster (feel free to organise it your way)
units = double(tabulate(cluster_id));
nunits = numel(units(:,1));
maxspikes = max(units(:,2));
%spiketimestamps = sparse(maxspikes,nunits); 
spiketimestamps = sparse(maxspikes,nunits); 
spiketimestamps_empty = zeros(nunits,1);
%spiketimestamps = tall(zeros(maxspikes,nunits));
a = 1;

for i = 1:nunits 
    i
    spiketimestamps(1:units(i,2),a)=(times(cluster_id==units(i,1)));
    empty_cluster = nnz(spiketimestamps(:,a));
    if empty_cluster <500
        %This deletes almost empty clusters and adds a true value into the 
        %matrix for empty cells
        spiketimestamps(:,a) = [];
        spiketimestamps_empty(i,1) = 1;
            
    else
        %This only saves the centers into the matrix which refer to a not
        %empty cell
        centres(a,:) = centres_temp(i,:);
        a = a+1;
    end

end
%Transfer timestamps from frames to seconds
spiketimestamps = spiketimestamps / Sampling;
clear centres_temp
disp ("Data Loaded");
     
     
     
 %% Spiketime validation
 %This rejects all cells which spike at a too high rate (10% or more of the
 %cells have a inter spike intervall of less than 10 milliseconds)
 min_distance = 0.01; %This is the maximal firing rate that is considered 
 %to be natural
 ISP = diff(spiketimestamps,1,1);
 ISP_neg = logical(ISP<min_distance);
 stx = length(spiketimestamps(1,:));
 sty = length(spiketimestamps(:,1));
 st_validated = NaN(1,stx);

 parfor i=1:length(spiketimestamps(1,:))
    stx_t = stx;
    sty_t = sty;
    ISP_temp = spiketimestamps(:,i);
    ISP_neg_temp = nnz(ISP_neg(:,i));
    nnz_temp = nnz(spiketimestamps(:,i)==0);
    nr_spikes = sty-nnz_temp;
    false_spikes = nr_spikes/ISP_neg_temp;
    st_validated(1,i) = false_spikes;
 end
 %Clusters with more than 10% of wrong spikes will be sorted out
 wrong_spikes = logical(st_validated>0.1);
 spiketimestamps(:,wrong_spikes) = [];
 centres(wrong_spikes,:) = [];
 spiketimestamps_empty(wrong_spikes,1) = 1;
 stx = stx-nnz(wrong_spikes);
 %find last nonzero element and reduce matrix size accordingly
 nnz_row = NaN(1,stx);
 for i = 1:stx
    [nnz_row(i),~] = find(spiketimestamps(:,i),1,'last');
 end
 st_end = nanmax(nnz_row);
 spiketimestamps = spiketimestamps(1:st_end,:);
     
 %% Get the stimulus time
 %In this section the trigger signal is read and information about the
 %stimulus is saved in different matrices
     
 %Load the stimulus file (Channel 1,2)
 [stimulus_file,stimulus_path] = uigetfile('*.mat','Select stimulus file');
 cd (stimulus_path);
 load(stimulus_file);

 %This function recognizes the different Epochs that were used
 %during the recording, based on the Epoch codes in the trigger channel
 Epochs = Arduino_Epochs(Ch01_02, 200, SamplingFrequency);
 
 %Get a logical matrix which indicates Epochs of Colour Noise
 Epochs.CNoise = Epochs.Epoch_code == single(0.35);
 Epochs.nCN = Epochs.CNoise == 0;
 
 %Here we calculate which epochs are unique and in which sequence they
 %appear
 Epochs.Epoch_code_unique = unique(Epochs.Epoch_code,'stable');
 Epochs.CNoise_unique = Epochs.Epoch_code_unique == single(0.35);
 %Add one loop colour noise information 



 %This path refers to the matlab files in which the stimulus
 %information for the different Epochs is saved
 stimulus_path = 'D:\Stimuli_Data\Arduino_Stim_Images\';

 %This function decodes the code in the trigger channel
 Epochs = Load_stim_info(Epochs, stimulus_path);
 %Create a cell which contains the unique kinds of stimuli shown 
 Epochs.Epochtext_single = unique(Epochs.Epochtext,'stable');

 
 if whole_stimulus == 0
    %Old Stuff should be removed in future
    
    
         %Find the number of stimuli that are repeated during one Epoch, this
     %is only beeing used in case no complete stimulus trace was shown.
     Epochs = Create_stimulus_info(Epochs,fff_repeat,0);
   
       
     
    
     
     
    
  
  
 end
 %% Bin the responses
 
 %Find the times of the end of every stimulus repetition

 %Calculate the bining so that the stimulus begin is in sync with an epoch
 %begin
     
 %Ask for the binsize 
 prompt = {"Enter the binsize youd like to use in seconds "};
 title1 = 'Binsize';
 dims = [1 35];
 definput = {'Binsize in second'};
 Epochs.binsize = str2double(inputdlg(prompt,title1,dims,definput));
 
 %This function substracts 1s from the stimulus start to account for the
 %pre stimulus window declared earlier.
 Epochs = pre_stim_window (Epochs, 1, Mode); 

 %This function calculates how many bins are required for every stimulus 
 Epochs = Bin_fitting_V2 (Epochs, Mode);


 %Just some old code which may be helpful sometimes
 %        for ii = 1:Epochs.nr_epochs
 %            Epochs.nr_bins(1,1,ii) = ceil((Epochs.Epochs_end(1,ii)-Epochs.Epochs_begin(1,ii))/Epochs.binsize);
 %        end
     

    

 


 %% Bining the responses OLD
% %In this section the spikes of the trials will be assigned to bins with a
% %specific size.
% 
% 
% %This function bins the spikes
% Bined_epochs = Epochs_bining_V3(Epochs, spiketimestamps,1);
% %Save the bined spikes into the Epochs structure as tall array
% Epochs.Bined_epochs = tall(Bined_epochs);
% %%
% %This function averages the number of spikes per bin for all stimulus
% %except the Colour Noise (Maybe we need to include CNoise in future...)
% [Averaged_Epochs,Epochs] = Responseaverage(Epochs,Bined_epochs,Mode);
% 
% %Transfer spikes per bins to spikes per second
% Averaged_Epochs_s = Averaged_Epochs * (1/Epochs.binsize);
% 
% %Smooth the responses
% Smoothened_averaged_spikes = smoothdata(Averaged_Epochs_s,'gaussian',2,'omitnan');
% %Save the smoothened traces in the Epochs structure as tall array
% Epochs.Smoothened_averaged_spikes = tall(Smoothened_averaged_spikes);
% 
% %Save the spiketimestamps as tall matrix
% Epochs.spiketimestamps = tall(full(spiketimestamps));

%Get the Epochs text for the whole loop


%% Epochs bining new (batch)
%This part checks how big how many cells are in the recording and processes
%the data either in one loop or creates batches with size 500 and processes
%these batches. This prevents memory chrashes. In the end the output data
%are smoothed bined spikes and the response quality index for each of the
%cells. 


 if length(spiketimestamps(1,:)) <= Batch
    Bined_epochs = Epochs_bining_V3(Epochs, spiketimestamps,1);

   
    %This function averages the number of spikes per bin for all stimulus
    %except the Colour Noise (Maybe we need to include CNoise in future...)
    [Averaged_Epochs,Epochs] = Responseaverage(Epochs,Bined_epochs,Mode);

    %Transfer spikes per bins to spikes per second
    Averaged_Epochs_s = Averaged_Epochs * (1/Epochs.binsize);

    %Smooth the responses
    Smoothened_averaged_spikes = smoothdata(Averaged_Epochs_s,'gaussian',2,'omitnan');
    %Save the smoothened traces in the Epochs structure as tall array
        
    RQC_epochs = double(Epochs.CNoise_unique == 0);

    Response_quality_idx = RQC(Epochs,RQC_epochs,Bined_epochs);
 else
    Nr_Batches_c = ceil(length(spiketimestamps(1,:))/Batch);
    %The last Batch has to be treated differently from the others as it
    %likely does not devide even by 500
    Nr_Batches_s = Nr_Batches_c - 1;
        
    stx_B = 1;
    for kk = 1:Nr_Batches_s
        kk
        spiketimestamps_temp = spiketimestamps(:,stx_B:stx_B+Batch-1);
        Bined_epochs = Epochs_bining_V3(Epochs, spiketimestamps_temp,1);
        [Averaged_Epochs,Epochs] = Responseaverage(Epochs,Bined_epochs,Mode);
        Averaged_Epochs_s = Averaged_Epochs * (1/Epochs.binsize);
        Smoothened_averaged_spikes_temp = smoothdata(Averaged_Epochs_s,'gaussian',2,'omitnan');
        RQC_epochs = double(Epochs.CNoise_unique == 0);
        Response_quality_idx_temp = RQC(Epochs,RQC_epochs,Bined_epochs);
            
            
        %Save data for outside the loop
        Smoothened_averaged_spikes(:,stx_B:stx_B+Batch-1) = Smoothened_averaged_spikes_temp;
        Response_quality_idx(stx_B:stx_B+Batch-1,1) = Response_quality_idx_temp;
        %Change indices
        stx_B = stx_B+Batch;
     end
        %This part is the same as above but only runs once for the
        %remaining cells which didnt devide evenly by 500
        Remain_S = length(spiketimestamps(1,:)) - Nr_Batches_s * Batch ;
        spiketimestamps_temp = spiketimestamps(:,stx_B:stx_B+Remain_S-1);
        Bined_epochs = Epochs_bining_V3(Epochs, spiketimestamps_temp,1);
        [Averaged_Epochs,Epochs] = Responseaverage(Epochs,Bined_epochs,Mode);
        Averaged_Epochs_s = Averaged_Epochs * (1/Epochs.binsize);
        Smoothened_averaged_spikes_temp = smoothdata(Averaged_Epochs_s,'gaussian',2,'omitnan');
        RQC_epochs = double(Epochs.CNoise_unique == 0);
        Response_quality_idx_temp = RQC(Epochs,RQC_epochs,Bined_epochs);
        
        Smoothened_averaged_spikes(:,stx_B:stx_B+Remain_S-1) = Smoothened_averaged_spikes_temp;
        Response_quality_idx(stx_B:stx_B+Remain_S-1,1) = Response_quality_idx_temp;
 end

        

 



 %% Plotting preperation
 %% Load pictures
 %    This section loads the pictures related to the trigger ids saved in the
 %    variable sequence

 %This function finds the arrays in the Epochs structure which contain the
 %information about how the stimulus looks like (Like the "FFF" array)
 sequence = read_single_stim_seq(Epochs);
 RGB_value = double(NaN(length(sequence),3,Epochs.nr_unique_epochs));
 [Image_Folder,Image_Path] = uigetfile('*.png','Select image folder');
    cd (convertCharsToStrings(Image_Path));
 %This loops over every entry of the "FFF" matrix and find the respective
 %picture saved in the folder
 for kk = 1:Epochs.nr_unique_epochs
    
    
 
    for ii = 0:length(sequence)-1
        if isnan(sequence(ii+1,kk)) == 0
            if sequence(ii+1,kk)< 10 
                temp_pic = imread(strcat((Image_Folder(1:end-5)),...
                num2str(sequence(ii+1,kk)),'.png'));
            elseif sequence(ii+1,kk) < 100 
                temp_pic = imread(strcat((Image_Folder(1:end-6)),...
                num2str(sequence(ii+1,kk)),'.png'));
            elseif sequence(ii+1,kk) < 1000 
                temp_pic = imread(strcat((Image_Folder(1:end-7)),...
                num2str(sequence(ii+1,kk)),'.png'));
            end
            RGB_value(ii+1,:,kk) = temp_pic(1,1,:); 
        end
    end
%  RGB_value = im2double(RGB_value);
  
  
 end
 %Translate the RGB values to matlab RGB values
 RGB_value = RGB_value/255;



 %% Calculate Kernels
 %%parameters
 %This again uses batches in case the size of the spiketimestamps is above
 %500.
 time_window = 2; %in s
 kbinsize = 0.001; %in s

 if want_Kernels == 1 && Mode == 0
 Kernels = calculate_kernels(Epochs,0.001,2,1:500);


 elseif want_Kernels == 1 && Mode == 1
    %Cut spiktimestamps into Batches of 500
    Batch = 500;
    if length(spiketimestamps(1,:)) <= Batch
        Kernels = calculate_Kernels_speed (Epochs,spiketimestamps, kbinsize, time_window);
    else
    Nr_Batches_c = ceil(length(spiketimestamps(1,:))/Batch);
    Nr_Batches_s = Nr_Batches_c - 1;
    Kernels_temp = NaN(4,time_window*1000+0.2*1000,length(spiketimestamps(1,:)));
    stx_B = 1;
    for kk = 1:Nr_Batches_s
        Kernels_temp(:,:,stx_B:stx_B+Batch-1) = calculate_Kernels_speed (Epochs,spiketimestamps(:,...
            stx_B:stx_B+Batch-1), kbinsize, time_window);
        stx_B = stx_B+Batch;
        kk
    end
    Remain_K = length(spiketimestamps(1,:)) - Nr_Batches_s * Batch ;
    Kernels_temp(:,:,stx_B:stx_B+Remain_K-1) = calculate_Kernels_speed (Epochs,spiketimestamps(:,...
            stx_B:stx_B+Remain_K-1), kbinsize, time_window);
    end
        
        
    
 Epochs.Kernels = tall(Kernels_temp);
 


 %This calculates the Kernel qualtiy index
 [KQI,KQI_C,KQI_past] = Quality_Kernels(Kernels_temp,4,0.1);


 Epochs.KQI = KQI;
 Epochs.KQI_C = KQI_C;
 Epochs.KQI_past = KQI_past;
 end 


 %% Clustering of Traces
 
%Will be done by Paul
% Smoothened_averaged_spikes = gather(Epochs.Smoothened_averaged_spikes);
% 
% Cluster_traces = Smoothened_averaged_spikes';
% 
% % Spike_clusters = clusterdata(Cluster_traces,'Maxclust',50);HowTo
% 
% [idx_1,C] = kmeans(Cluster_traces,50,'Distance','correlation',...
%     'Replicates',5);
% Spike_clusters = idx_1;



 %% Save the Data
 %First we have to write all the necessary data into the Epochs structure
 % Epochs.Best_cells = Best_cells;
 % Epochs.Response_quality_idx = Response_quality_idx;
 Epochs.centres = tall(centres);
 % Epochs.Spike_clusters = Spike_clusters;
 Epochs.Smoothened_averaged_spikes = Smoothened_averaged_spikes;
 Epochs.RGB_value = tall(RGB_value);
 Epochs.SamplingFrequency = SamplingFrequency;
 Epochs.spiketimestamps = spiketimestamps;
 if Mode == 0
 Epochs.FFF_repeat = fff_repeat;
 Epochs.r_repeat = r_repeat;
 end

 %This opens a dialog box to save the data
 [file,path] = uiputfile('Phase.mat');
 cd(path);
 save(file,'Epochs', '-v7.3');

end %This is the end of the part of the script which processes unsaved/new 
%data when the user answers the questions about the wish to load saved data
%with "no".

%% Inspect single clusters
%Here different graphs are plotted. This part is still under construction


current_cluster = 0; %Makes sure we start with the first cluster
while true %This loops as long as the user breaks the loop by input
    close all
    
%Ask for the cluster(or cell) the user wants to see

prompt = {"Enter the number of the cluster you'd like to see"};
title1 = 'Cluster Selection';
dims = [1 35];

definput = {num2str((current_cluster)+1)};
%Selection of the user is saved in current_cluster
current_cluster  = str2double(inputdlg(prompt,title1,dims,definput));


es = 1; %This variable indicates the number of the selected stimulus(based
%on the list below)
while exist('es','var')
    
 % Get available stimuli
list = {'Chirp', 'Ramp','FFF','FFF380', 'FFF430','FFF480', 'Dark Flash', 'FFF560',...
    'FFF505', 'Colour Noise', 'FFF630', 'CNoise', 'SS380','SS430', 'SS480', 'SS505', 'SS560', 'SS630', 'LStep430'};
%We need this extra cell array so that we can compare which stimuli are
%used in the data

list1 = {{'Chirp'}, {'Ramp'},{'FFF'}, {'FFF380'},{'FFF430'},{'FFF480'}, {'Dark Flash'}, {'FFF560'},...
    {'FFF505'}, {'Colour Noise'}, {'FFF630'},{'CNoise'}, {'SS380'},{'SS430'}, {'SS480'}, {'SS505'}, {'SS560'}, {'SS630'}, {'LStep430'}};
avail_stim = strings(1,Epochs.nr_unique_epochs);

for ss = 1:Epochs.nr_unique_epochs
    %Here we check which stimuli have been used during the recording by
    %comparing the list to Epochs.Epochtext
    avail_stim(ss) = string(Epochs.Epochtext_single(ss));
    idx(ss) = find(strcmp([list1{:}], avail_stim(ss)));
end

new_list = list(idx);
[es,~] = listdlg('ListString',new_list);
es = idx(es);


if length(es) == 1 %If the user chooses to see a single stimulus only this
    %part is less and less used an probably redundant in the future.
current_epoch = epocheval(es);
current_epoch = find(Epochs.Epoch_code == single(current_epoch));
current_epoch = current_epoch(1);

%Exclude Colour noise from the plotting steps
colour_idx = find(Epochs.Epoch_code == single(0.35));
Epochs.CNoise_epoch = colour_idx(1);

if isnan(Epochs.CNoise_epoch) == 0
    Epochs.nr_epochs_plot = Epochs.nr_unique_epochs - 1;
end

%Find the begin of the epoch (in bins)

Plot_E_b = Epochs.Epochs_begin - Epochs.Epochs_begin(1);
Plot_E_b = ceil05(Plot_E_b,0.005);
Plot_E_b = Plot_E_b(1:Epochs.nr_unique_epochs);
Plot_epochs_begin = Plot_E_b;
Plot_E_b = Plot_E_b/Epochs.binsize;
Plot_E_b(1) = 1;

idx_Plot(1) = current_epoch;
idx_Plot(2) = current_epoch+1;
nr_bins = Plot_E_b(idx_Plot(2)) - Plot_E_b(idx_Plot(1))+1;

%Calculate the respective time
% x_value = (Epochs.binsize:Epochs.binsize:Epochs.Epochs_duration(current_epoch));

temp_sbe = Smoothened_averaged_spikes((Plot_E_b(idx_Plot(1)):...
    Plot_E_b(idx_Plot(2))),current_cluster);
end_time = length(temp_sbe)*Epochs.binsize;
x_value = (0:Epochs.binsize:end_time-Epochs.binsize);

%Find the spiketrains

current_spiketimestamp = gather(Epochs.spiketimestamps(:,current_cluster));
%Find the right times
spiketrain_epoch = epocheval(es);
spiketrain_epoch = find(Epochs.Epoch_code == single(spiketrain_epoch));

spiketrain_begin = squeeze(Epochs.stimulus_starts_pw(1,1,spiketrain_epoch));
spiketrain_end = Epochs.Epochs_end(1,spiketrain_epoch);
nr_repeats = Epochs.nr_epochs/Epochs.nr_unique_epochs;

temp_spiketrain = NaN(length(current_spiketimestamp(:,1)),nr_repeats);
%Split the complete spiketrain into the different trials
for rr = 1:nr_repeats
    spiketrain_idx = logical((current_spiketimestamp >= spiketrain_begin(rr))...
        .*(current_spiketimestamp <=spiketrain_end(rr)));
    nr_spikes = nnz(spiketrain_idx);
    temp_spiketrain(1:nr_spikes,rr) = current_spiketimestamp(spiketrain_idx,1);
    temp_spiketrain(:,rr) = temp_spiketrain(:,rr)-spiketrain_begin(rr);
    [t,~] = find(isnan(temp_spiketrain(:,rr)));
    lastnonNaN(1,rr) = t(1,1);


end

lastnonNaN = max(lastnonNaN);
y_value_temp = ones(1,lastnonNaN-1);
temp_spiketrain = temp_spiketrain(1:lastnonNaN-1,:);


%Get the data for the stimulus plot
%Erase the NaNs
RGB_value_temp = gather(Epochs.RGB_value(:,:,current_epoch));
[t,~] = find(isnan(RGB_value_temp(:,:,1)));
t = min(t)-1;

RGB_value_temp = RGB_value_temp(1:t,:);

% %Generate the values for the xaxis for the stimulus plot
% 
downsample_factor = Epochs.binsize/trigger_freq;
RGB_value = downsample(RGB_value_temp,downsample_factor);
%Mean number of bins, but this has to be changed so that there is only
%one right number of epochs from the beginning
mean_bins = mean(Epochs.nr_bins(1,1,spiketrain_epoch),3);
graphx = (Epochs.binsize:Epochs.binsize:Epochs.Epochs_duration(current_epoch));
temp_sfg =  ones(length(graphx),1);
RGB_value_graph = RGB_value;







ax1 = subplot(3,1,1);

for ii = 1:nr_repeats
y_value = y_value_temp+0.5*(ii-1);    
scatter(temp_spiketrain(:,ii),y_value,'.','k');
hold on
end
xlim 'auto'
ylabel('Trials') 







ax2 = subplot(3,1,2);

%bar(x_value,temp_sbe);
plot(x_value,temp_sbe)
ylabel('Spikes per s') 

ax3 = subplot(3,1,3);
hold on
stimulus_plot = bar(graphx,temp_sfg,2,'FaceColor','flat','EdgeColor','flat');
for kk = 1:length(RGB_value_graph)
    
stimulus_plot.CData(kk,:) = RGB_value_graph(kk,:);
end
xlim([0 Epochs.Epochs_duration(current_epoch)])
linkaxes([ax1,ax2,ax3],'x')
ylim auto
xlim ([0 end_time])
ylabel('Stimulus') 
xlabel('Time in s') 




elseif length(es) == length(idx) %This plots the whole traces in once
    
    %Check if colour noise is in the epochs
    CNoise = find(strcmp(new_list, 'CNoise'));
    CNoise_l = logical(CNoise);
    plot_list = new_list;
    if CNoise_l == 1
        %Here we delet the CNoise from the list of epochs to plot
        plot_list{CNoise} = [];
        nr_epochs_whole = Epochs.nr_unique_epochs-1;
    end
    %Get the data for all epochs from the tall array
    whole_trace = gather(Epochs.Smoothened_averaged_spikes(:,current_cluster));
   
    %Look how long the trace will be and create an array with the
    %information for the xaxis
    whole_trace_l = length(whole_trace(:,1));
    whole_trace_t = whole_trace_l * Epochs.binsize;
    x_whole_trace = (Epochs.binsize:Epochs.binsize:whole_trace_t);
    
    
    
    %Find the spiketrace
    whole_spiketrain = gather(Epochs.spiketimestamps(:,current_cluster));
    %find the last epoch of every stimulus loop, so that we can cut the spiketrain there
    cut_epoch = Epochs.Epoch_code(nr_epochs_whole);
    cut_epochs = Epochs.Epoch_code == cut_epoch;
    cut_time = Epochs.Epochs_end(cut_epochs);
    cut_begin = Epochs.Epoch_code(1);
    cut_begin = Epochs.Epoch_code == cut_begin;
    
    
    %Check how often the stimulus loop was repeated and create a matrix to
    %fit in all spikes which happend during a stimulus loop
    stimulus_repeat = Epochs.loop_repeats;
    spiketrain_trials = NaN(length(whole_spiketrain(:,1)),stimulus_repeat);
    spiketrain_begins = Epochs.stimulus_starts_pw(cut_begin);
    
    %Check the spiketimestamps for which spikes fall into the timing at
    %which the stimulus was shown and order the spikes into the respective
    %trace
    for rr = 1:stimulus_repeat
        c = spiketrain_begins(rr);
        cut_spikes = (whole_spiketrain > c) .* (whole_spiketrain < cut_time(rr));
        cut_spikes = logical(cut_spikes);
        cut_spikes_c = nnz(cut_spikes);
       
        spiketrain_trials(1:cut_spikes_c,rr) = whole_spiketrain(cut_spikes);
        spiketrain_trials(:,rr) = spiketrain_trials(:,rr) - spiketrain_begins(rr); 
        
    end
    
    %The matrix which was created above is too big (to make sure all spikes
    %will fit inside) here we cut it to its real length
    last_NaN = max(find_ndim(~isnan(spiketrain_trials),1,'last'));
    spiketrain_trials = spiketrain_trials((1:last_NaN),:);
    %This is the y value which we need to plot the spikes(dots) in the
    %rasterplot
    spiketrain_y = ones(length(spiketrain_trials(:,1)),1);
    
    
    
    %% Get the stimulus data
    %In this section the information about the stimulus itself is loaded
    %and prepared for plotting
    Epoch_code_temp = Epochs.Epoch_code(1,(1:nr_epochs_whole));
    
    C_Noise_Epoch = Epoch_code_temp == single(0.35);
    C_Noise_Epoch_neg = find(C_Noise_Epoch ~= 1);
   
    RGB_whole_trace = squeeze(gather(Epochs.RGB_value(:,:,C_Noise_Epoch_neg)));
    %This is just some Matlab matrix transformation to get a 2D matrix with
    %all the RGB values in rows which are in the 3rd dimension before
    RGB_whole_trace = permute(RGB_whole_trace,[1,3,2]);
    RGB_whole_trace = reshape(RGB_whole_trace,[],3);
    %Remove the NAN values
    RGB_whole_trace = RGB_whole_trace((isnan(RGB_whole_trace(:,1)) == 0),:);
    x_stimulus_plot = (0.001:0.001:whole_trace_t);
   % Memory and time saving option for the ploting
  
   if memory_save == 1
    downsample_factor = Epochs.binsize/trigger_freq;
    RGB_whole_trace = downsample(RGB_whole_trace,downsample_factor);
    x_stimulus_plot = x_whole_trace;
   end
    temp_sfg = ones(length(RGB_whole_trace),1);
    
    
    
    %% Plot
    
    ax1 = subplot(4,1,1);
    

    for ii = 1:stimulus_repeat
    y_value = spiketrain_y+0.5*(ii-1);    
    scatter(spiketrain_trials(:,ii),y_value,'.','k');
    hold on
    end
   
    ylabel('Trials')
    set(ax1,'XTick',[])
    ax1.YTick(1) = [];
    ax1.YTick(1) = Epochs.loop_repeats/2+0.5;
    ax1.YTickLabel = num2str(Epochs.loop_repeats);
    ax1.XColor = [1 1 1];
   
    
    
    ax2 = subplot(4,1,2);

    ax21 = plot(x_whole_trace,whole_trace,'k');
    ylabel('Spikes [Hz]')
    set(ax1,'XTick',[])
    set(ax21.Parent,'XTick',[])
    ax1.YTick(1) = [];
    ax21.Parent.XColor = [1 1 1];
    
    ax2.OuterPosition(2) = ax2.OuterPosition(2)+0.05;
    
    
    
     [Coeffs,f] = cwt(whole_trace,(1/Epochs.binsize));
%     Coeffs = flipud(Coeffs);
%     f = flipud(f);
    SCimg = wscalogram('',Coeffs,'scales',f,'ydata',whole_trace,'xdata',x_whole_trace);
    ax3 = subplot(4,1,3);
    hold on
    spec = imagesc(x_whole_trace,f,SCimg);
    ylim([10 20])
    ylabel('Frequency [Hz]')
    ax3.OuterPosition(4) = ax3.OuterPosition(4)*0.5;
    ax3.OuterPosition(2) = ax3.OuterPosition(2)+0.18;
    set(ax3,'XTick',[])
    ax3.XColor = [1 1 1];
    
    ax4 = subplot(4,1,4);
    
        hold on
%         stimulus_plot = bar(x_whole_trace,temp_sfg,2,'FaceColor','flat','EdgeColor','flat');
        stimulus_plot = bar(x_stimulus_plot,temp_sfg,2,'FaceColor','flat','EdgeColor','flat');
        for kk = 1:length(RGB_whole_trace)
    
        stimulus_plot.CData(kk,:) = RGB_whole_trace(kk,:);
        end
             
    ax4.OuterPosition(4) = ax4.OuterPosition(4)*0.5;
    ax4.OuterPosition(2) = ax4.OuterPosition(2)+0.28;
    set(ax4,'YTick',[])
    xlabel ('Time [s]')

    linkaxes([ax1,ax2,ax3,ax4],'x')
    
    
    %% plot Kernel
    if want_Kernels == 1
    Kernel_plot = squeeze(gather(Epochs.Kernels(:,:,current_cluster)));
    
    colorstring = 'mbgr';
    xaxis_k = (-1.999:0.001:0.2);
     figure
    for kk = 1:length(Kernel_plot(:,1))
    Kernel_plot = Kernel_plot./max(max(Kernel_plot));
    plot(xaxis_k,Kernel_plot(kk,:),'Color',colorstring(kk),'LineWidth',2)
    
    hold on
    end
%     line([0 0], [-5 5],'Color','k'); 
    xlim ([-0.5 0.2])
    set(gca, 'YTick', [])
    end
    
end
    
%% Decision
%Ask the user how to proceed after the data has been plotted. The options
%are: Seeing another single epoch, seeing another cell or seeing all the
%cells which belong to the same cluster

group = 'Decision';
pref =  'Conversion';
title1 = 'Resume?';
quest = {'Do you want to have a look at another epoch?, Or do you want to see'...
    'all other cells with the same response characteristics?'};
pbtns = {'Yes','No','Other cells'};

[pval,~] = uigetpref(group,pref,title1,quest,pbtns);
s1 = 'yes';
s2 = 'no';
s3 = 'other cells';
tf = strcmp(s1,pval);
tf1 = strcmp(s2,pval);

if tf1 == 1
    try
        close 1
        break
    catch
        break
    end
end

close 1    

if tf == 0 && tf1 == 0
    
    % find the cells which fall into the same cluster
    cluster_cell = Epochs.Spike_clusters(current_cluster);
    same_cluster = Epochs.Spike_clusters == cluster_cell;
    l_same_cluster = nnz(same_cluster);
    same_cluster_idx = find(same_cluster);
    %save the respective traces in a new vector
    
    same_cluster_t = gather(Epochs.Smoothened_averaged_spikes(:,same_cluster_idx));
    
    for ll= 1:l_same_cluster
      ax(ll) =  subplot(l_same_cluster+1,1,ll);
        plot(x_whole_trace,same_cluster_t(:,ll));
        title(['Cluster ',num2str(same_cluster_idx(ll))],'FontSize',6);
        
        hold on
        
    end
    hold off
    
  ax(ll+1) = subplot(l_same_cluster+1,1,ll+1);
    
        hold on
%         stimulus_plot = bar(x_whole_trace,temp_sfg,2,'FaceColor','flat','EdgeColor','flat');
        stimulus_plot = bar(x_stimulus_plot,temp_sfg,2,'FaceColor','flat','EdgeColor','flat');
        for kk = 1:length(RGB_whole_trace)
    
        stimulus_plot.CData(kk,:) = RGB_whole_trace(kk,:);
        end
    
    linkaxes(ax,'x')
    
    
    %% Plot the location on the chip
    
    MEAY = ones(64,64);
    MEAX = (1:1:64);
    
MEAf = figure;
for mm = 1:64
    
    MEAY(mm,:) = MEAY(mm,:)*mm;
    ax = scatter(MEAX,MEAY(mm,:),'s','MarkerFaceColor',[0.9 0.9 0.9],'MarkerEdgeColor', 'None');
    
    hold on
end

for mm = 1:l_same_cluster
scatter(Epochs.centres(same_cluster_idx(mm),1),Epochs.centres(same_cluster_idx(mm)...
    ,2),'r', 'filled');
text(Epochs.centres(same_cluster_idx(mm),1),Epochs.centres(same_cluster_idx(mm),2),...
    ['  Cell ',num2str(same_cluster_idx(mm))]);
xlim ([0 64])
ylim ([0 64])
set(gca,'visible','off')
end
 

% Plot the mean response trace
mean_c_trace = mean(same_cluster_t,2);

figure
mx1 = subplot(2,1,1);
plot(x_whole_trace,mean_c_trace)

hold on
mx2 = subplot(2,1,2);
%         stimulus_plot = bar(x_whole_trace,temp_sfg,2,'FaceColor','flat','EdgeColor','flat');
        stimulus_plot = bar(x_stimulus_plot,temp_sfg,2,'FaceColor','flat','EdgeColor','flat');
        for kk = 1:length(RGB_whole_trace)
    
        stimulus_plot.CData(kk,:) = RGB_whole_trace(kk,:);
        end
        
linkaxes([mx1,mx2],'x')

    

    
   
    
end
    
    
    
    

end




      
  
  
% Calculating the Fano factor which is the variance in the number of spikes 
%of a single measurement divided by the mean of all spikes
% spikecount = zeros(nr_repeats,1);
% for ii = 1:nr_repeats
% spikecount(ii,:) = length(spiketrains_cluster(~isnan(spiketrains_cluster...
%     (:,ii))));
% end
% 
% fano_factor = (std(spikecount)^2)/nanmean(spikecount);
 
% Ask if loop should continue

group = 'Decision';
pref =  'Conversion';
title1 = 'Resume?';
quest = {'Do you want to have a look at another cluster?'};
pbtns = {'Yes','No'};

[pval,~] = uigetpref(group,pref,title1,quest,pbtns);

% s3 = 'continue';
% tf = strcmp(s1,pval);
% tf1 = strcmp(s3,pval);
tf1 = strcmp(s2,pval);

if tf1 == 1
    break
end

    
    
end   

   
    







 


