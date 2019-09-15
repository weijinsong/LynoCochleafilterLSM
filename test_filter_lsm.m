clear;

%% Create Filter
opt.Fs = 8000;
opt.EarBreakFreq = 1000.0;
opt.EarQ = 8;
opt.EarStepFactor = 0.25;
opt.OriginalEarZeroOffset = 0.5;
opt.OriginalEarSharpness = 5.0;
opt.EarZeroOffset = 1.5;
opt.EarSharpness = 5.0;
opt.EarPremphCorner = 300.00;

[earfilter, cf] = CreateLynoCochleaFilter(opt);

%%create BSA filter
hearfilter = [0.0148264930711210,-0.0545957356107501,-0.00185072469746768,-0.0576891682999051,-0.0585522017011255,-0.0206252924614475,-0.138288795097396,0.0332863133250078,-0.207887220273215,0.0716629673876838,0.764556357556245,0.0716629673876838,-0.207887220273215,0.0332863133250078,-0.138288795097396,-0.0206252924614475,-0.0585522017011255,-0.0576891682999051,-0.00185072469746768,-0.0545957356107501,0.0148264930711210];
hearfilter = hearfilter - min(hearfilter);
hearfilter = hearfilter / max(abs(hearfilter)) * 0.29;

%% create LSM
lsmopt.n = 64;
lsmopt.r = 1;
lsmopt.tm = 32;
lsmopt.tc = 64;
lsmopt.tf = 2;
lsmopt.dt = 1;
lsmopt.vth = 20;
lsmopt.kee = 0.45;
lsmopt.kei = 0.3;
lsmopt.kie = 0.6;
lsmopt.kii = 0.15;
lsmopt.wee= 3;
lsmopt.wei= 6;
lsmopt.wie= -2;
lsmopt.wii= -2;
lsm = LSM(lsmopt);

%% read wav_list
filename = './recordings/wav_list.txt';
sound_data =[];
wav_list = textread(filename, '%s');
wav_data = [];
len = size(wav_list, 1);
lsmout = [];
label = ones(1,len);
ii = 0;
for wavindex = 1 : 1 : len
	wav_name = char(strcat('./recordings/', wav_list(wavindex)));
    name = char(wav_list(wavindex));
    ii = ii + 1;
    label(ii) = str2num(name(1));
    disp(['number : ', num2str(wavindex), ' wave name : ', wav_name]);
	[wav_test, fs] = audioread(wav_name);
    wav_data = [wav_data; wav_test];
%     label(i) = str2
	time = length(wav_test);
    display(['wave length :', num2str(time)]);
	%% Applay Lynocochlea filter
    disp("Applay Lynocohlea Filter");
	y = ApplyLynoCochleaFilter(wav_test', earfilter, opt);
	channel = size(y, 1);
    disp(['Channel : ', num2str(channel)]);
	%% Applay BSA
    disp(["Applay BSA"]);
	maxy = max(y');
	for i = 1 : size(y, 1)
    	y(i, :) = y(i, :) ./ maxy(i);
	end
	multi = 17;
	my = zeros(size(y,1), size(y,2)*multi);
	for i = 1 : multi
    	my(:,i:multi:end) = y(:,:);
	end
	Hd = hfilter_design;
	hfilter = Hd.Numerator;
	hfilter = hfilter - min(hfilter);
	hfilter = hfilter / max(abs(hfilter)) * 0.23;
	bsath = 0.75;
	bsast = BSA(hfilter, my, bsath);
	bsay = [];
	
    for i = 1 : size(bsast, 1)
    	convt = conv(bsast(i,:), hfilter, 'full');
    	bsay = [bsay; convt(1:time*multi)];
    end

    bsaerror = bsay - my;
    Eacgy = sum(my.^2, 2);
    Ebsaerror = sum(bsaerror.^2, 2);
    BSASNDR = 20*log10(Eacgy./Ebsaerror);
    disp(['SNDR :', num2str(BSASNDR')]);
    
    spike = zeros(size(bsast, 1), size(bsast,2)/multi);
	for i = 1 : multi
	    spike(:,:) = max(spike(:,:), bsast(:,i:multi:end));
	end	
	%% Applay LSM
    disp(["Applay LSM"]);
	[lsm, lsmspike] = runLSM(lsm, spike);
	% squarespike = reshape(lsmspike, [4,8]);
	% imshow(1-squarespike);
	plot(lsmspike);
    grid on;
    pause(0.001);
	lsmout = [lsmout; lsmspike];
end
save('spike_out', 'spike', 'label');
save('wavlsm.mat', 'lsmout', 'label');
save('wavdata.mat', 'wav_data');
%% BP Net
clear;
load wavlsm.mat;

m= size(lsmout,1);
k = 1;
train_x = double(lsmout(1 :k: end,:));
train_y = zeros(size(train_x,1),10);

ii = 0;
for i = 1 : k : m
    ii= ii + 1;
    for j = 1 : 10
        if j == label(i)+1
            train_y(ii, j) = 1;
        end
    end
end
[train_x, mu, sigma] = zscore(train_x);

rand('state', 0);
nn = nnsetup([64, 10]);
opts.numepochs = 1000;
opts.batchsize = 50;
[nn, L] = nntrain(nn, train_x, train_y, opts);
[er, bad] = nntest(nn, train_x, train_y);
assert(er< 0.08, "too big error");


