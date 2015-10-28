function [numcalls, peakpos, peakval, neglogli] = dofit_fromcsv_GLM_zf4f(csvpath, runlabel, k, indexmapper, startsecs, endsecs, plotpath, csvoutpath)
% [peakpos, peakval] = dofit_fromcsv_GLM_zf4f(csvpath, runlabel, k, indexmapper, startsecs, endsecs, plotpath, csvoutpath)
%
% load some zf4f-format data and analyse "as if" it were cell spiking data. returns analysed data.
% also does a plot and writes it to a file in the folder named by 'plotpath'. if 'plotpath' is '' or 0 it DOESN'T plot. to plot in cwd use '.'
% 'csvoutpath' parameter is analogous, and is about writing CSV data out to file

global RefreshRate;
RefreshRate = 1;  % the "RefreshRate" is the samplerate of the stimulus (in Hz). I don't currently use stimulus so I set it to 1. Below, "DTsim" sets the time-resultion used in the model.

plotcols = {'r', 'b', 'g', 'm', 'y'};

numcalls = zeros(k,1);
peakpos = zeros(k);
peakval = zeros(k);

printf('dofit_fromcsv_GLM_zf4f(%s, %s, %i, %s, %i, %i, %s, %s)\n', csvpath, runlabel, k, mat2str(indexmapper), startsecs, endsecs, plotpath, csvoutpath);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Load the CSV data
events = csvread(csvpath);
%size(events)
events = events((events(:,1) >= startsecs) & (events(:,1) <= endsecs), [1,3]);
%size(events)

tsp = cell(1,k);
for whichn=1:k
	matchid = indexmapper(whichn)-1;
	tsp{whichn} = (events(events(:,2)==matchid, 1) - startsecs) * RefreshRate;   % subtracting startsecs, and converting to units of RefreshRate
	numcalls(whichn) = size(tsp{whichn}, 1);
	printf('Bird %i has %i events\n', whichn, numcalls(whichn));
end;
fflush(stdout); % NB octave-only

endsecs_actual = max(events(:,1)) + 0.1;   % this tells us how far into the distance we actually need to look.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%  1.  Set parameters

DTsim = .005; % Bin size for simulating model & computing likelihood (in units of stimulus frames)
nkt = 40;    % Number of time bins in filter;
ttk = [-nkt+1:0]';
ggsimsolo = cell(k,1);
for whichn = 1:k
	ggsimsolo{whichn} = makeSimStruct_GLM(nkt,DTsim);  % Create GLM struct with default params
end;
ggsim = makeSimStruct_GLMcpl(ggsimsolo{1:k});


%% 3. Set up the "stimulus" appropriately (here it's zeros)
slen = round((endsecs_actual-startsecs) * RefreshRate);  % Stimulus length (frames)
swid = 1;
Stim = zeros(slen,swid);





% -------------- Compute STAs------------
nsp = length(tsp{1});
stas = cell(k,1);
for whichn = 1:k
	sta0 = simpleSTC(Stim,tsp{whichn},nkt);
	stas{whichn} = reshape(sta0,nkt,[]); 
end;


%% 4. Do ML fitting of GLM params
gg = cell(k, 1);
neglogli = 0;
opts = {'display', 'iter', 'maxiter', 100};
for whichn = 1:k
	%fprintf('Fitting bird #%i\n', whichn);
	gg0 = makeFittingStruct_GLM(stas{whichn},DTsim,ggsim,whichn);  % Initialize params for fitting struct w/ sta
	% NOTE: the call above imposes an "absref" (absolute refactory period) of 10 * DTsim. Happily this is extremely reasonable in the zf4f case.
	gg0.ih = gg0.ih*0;  % Initialize to zero
	gg0.dc = gg0.dc*0;  % Initialize to zero

	gg0.tsp = tsp{whichn};   % cell spike times (vector)
	gg0.tsp2 = tsp(setdiff(1:k, whichn));  % spike trains from "coupled" cells (cell array of vectors)
	gg0.tspi = 1; % 1st spike to use for computing likelihood (eg, can ignore 1st n spikes)
	[gg{whichn}, neglogli_each] = MLfit_GLM(gg0, Stim, opts); % do ML (requires optimization toolbox)
	printf('MLfit #%i gets neglogli %g\n', whichn, neglogli_each);
	neglogli += neglogli_each;
end


%% --- Calc summary stats - used for csv and for returning ----------------------------
for whichn = 1:k
	for fromn = 1:k
		if whichn==fromn
			ihdata = gg{whichn}.ih;
		elseif whichn<fromn
			ihdata = gg{whichn}.ih2(:, fromn-1);
		else
			ihdata = gg{whichn}.ih2(:, fromn);
		end
		plotx = gg{whichn}.iht;
		ploty = exp(gg{whichn}.ihbas*ihdata);
		[peakvalraw, peakposraw] = max(ploty);
		peakpos(fromn,whichn) = plotx(peakposraw) / RefreshRate;
		peakval(fromn,whichn) = peakvalraw;
	end
end

%% --- Plot results ----------------------------
if plotpath
	h = figure(3);
	clf;

	set (h,'papertype', '<custom>');
	set (h,'paperunits','inches');
	set (h,'papersize',[6 5]);
	set (h,'paperposition', [0,0,[6 5]]);
	set (0,'defaulttextfontsize', 10);
	set (0,'defaultaxesfontsize', 10);

	legendargs = cell(k+2,1);
	for whichn = 1:k
		legendargs{whichn} = sprintf('to %i', whichn);
	end
	legendargs{k+1} = 'location';
	legendargs{k+2} = 'northeast';

	ttk = -nkt+1:0;

	numrows = ceil(sqrt(k));
	numcols = ceil(k/numrows);
	for fromn = 1:k
		subplot(numrows, numcols, fromn); % ----------------------------------
		hold on;
		for whichn = 1:k
			plotcol = plotcols{mod(whichn-1, numel(plotcols))+1};
			if whichn==fromn
				ihdata = gg{whichn}.ih;
				plotcol = 'k--';
			elseif whichn<fromn
				ihdata = gg{whichn}.ih2(:, fromn-1);
			else
				ihdata = gg{whichn}.ih2(:, fromn);
			end
			plotx = gg{whichn}.iht;
			ploty = exp(gg{whichn}.ihbas*ihdata);
			plot(plotx, ploty, plotcol);
			ylim([0, 5]);
		end;
		title(sprintf('Bird %i: exp(kernels) %s', fromn, runlabel));
		legend(legendargs{1:k+2});
		axis tight;
	end;
	xlabel('time (frames)')

	disp(sprintf('Saving %s/zf4f_glm_kernels_%s.png', plotpath, runlabel));
	saveas(h, sprintf('%s/zf4f_glm_kernels_%s.png', plotpath, runlabel));

	sleep(2);
else
	disp '  (not plotting)';
end



if csvoutpath
	outfnamestem = sprintf('%s/zf4f_glm_stats_%s', csvoutpath, runlabel);
	csvfp_0d = fopen(sprintf('%s_0d.csv', outfnamestem), 'w');
	csvfp_1d = fopen(sprintf('%s_1d.csv', outfnamestem), 'w');
	csvfp_2d = fopen(sprintf('%s_2d.csv', outfnamestem), 'w');
	% headers
	fprintf(csvfp_0d, 'runname,neglogli\n');
	fprintf(csvfp_1d, 'runname,individ,numcalls\n');
	fprintf(csvfp_2d, 'runname,frm,too,peakval,peaklag\n');
	% data
	fprintf(csvfp_0d, '%s,%g\n', runlabel, neglogli);
	for whichn = 1:k
		fprintf(csvfp_1d, '%s,%i,%i\n', runlabel, whichn, numcalls(whichn));
		for fromn = 1:k
			fprintf(csvfp_2d, '%s,%i,%i,%g,%g\n', runlabel, fromn, whichn, peakval(fromn,whichn), peakpos(fromn,whichn));
		end
	end
	fflush(csvfp_0d);
	fclose(csvfp_0d);
	fflush(csvfp_1d);
	fclose(csvfp_1d);
	fflush(csvfp_2d);
	fclose(csvfp_2d);
	sleep(2);
else
	disp '  (not writing csv)';
end

