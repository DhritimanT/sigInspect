function annot = sigInspectClassify(signal,fs,method, varargin)
% function annot = sigInspectClassify(signal,varargin)
% classify artifacts in each second of provided micro-EEG signal
% 
% IN: 
%   signal - micro-EEG signal vector (or signal matrix with channels in rows)
%   fs     - sampling frequency in Hz
%   method - classification method:
%           'psd' - normalized PSD spectrum thresholding, based on [1]
%                  (default) 91% train /88% test set accuracy on EMBC data
%                   threshold based on [2]
%           'tree'- pre-trained decision tree, based on multiple features,
%                   trained on a multi-centric database from [2]
%           'cov' - not yet implemented
%   params - optional parameters for some of the classification methods:
%          for 'psd': detection trheshold (default:0.01)
%          for 'cov' three parameters:
%                    - threshold (default 1.2 based on [2])
%                    - winLength: length of signal segment (default 0.25s)
%                    - aggregPerc: what proportion of one second window has
%                      to be marked as artifact to mark the whole sec. as
%                      artifact (deafault: winLength)
%           (default values based on [2])
% OUT:
%   annot - logical vector of annotation for each second of input signal.
%           true = artifact, false = clean signal
% 
% E. Bakstein 2015-06-29
% 
% [1] Bakstein, E. et. al.: Supervised Segmentation of Microelectrode Recording Artifacts Using Power Spectral Density, in Proceedings of IEEE EMBS, 2015
% [2] Bakstein, E.: Deep Brain Recordings in Parkinson's Disease: Processing, Analysis and Fusion with Anatomical Models, Doctoral Thesis, October 2016


% input checks
if(nargin<2)
    error('sampling frequency must be specified')
end

if(nargin<3 || isempty(method))
    method='psd';
end
    
if(isempty(signal))
    annot=[];
    return;
end

if(length(signal)<fs)
    error('signal must be at least 1s long');
end

[Nch,N] = size(signal); % number of channels + samples
Ns = ceil(N/fs);       % number of seconds


% ---- CLASSIFIER PARAMETERS ----

% features to be computed
switch(method)
    
    case {'psd','psdPrg'}
        % classifier parameters
        if(nargin>3 && isnumeric(varargin{1}))
            % user-defined threshold value
            psdThr = varargin{1};
            if(psdThr<0 || psdThr > .03)
                warning('recommended threshold range for psd method is between 0.005 and 0.02. The value provided (%.03f) may lead to unexpected results.',psdThr)
            end                
        else
            % pre-trained threshold
            if(strcmp(method,'psd'))            
                psdThr = .01;   % threshold trained on the multi-center data
            else            
                psdThr = .0085; % threshold trained on the Prague data only 
            end
        end
        % features
        featNames={'maxNormPSD'}; % definition of dataset columns
        featComp = [1];           % features actually computet (for compatibility with dec. tree)        
        method = 'psd';
    
    case {'tree', 'treePrg'}
        % load classifier params
        try
            classif = load('sigInspectClassifiers.mat'); % load pre-trained classifiers
        catch err        
            error('could not load precalculated classifiers: search sigInspect root for the file sigInspectClassifers.mat (necessary for the tree-based classifiers)')
        end
        if(strcmp(method,'tree'))
            classif.tree = classif.treeAll;
        else
            classif.tree = classif.treePrg;
        end
        % features to compute
        featNames = classif.featNames; % all 19 features have to be in the set 
        featComp = setdiff(unique(classif.tree.var),0); % only some are needed (non-nan)
        method = 'tree';
    case 'cov'
        featNames = {};
        covThr = 1.2;
        winLength = .25;
        aggregPerc = winLength;
        if(nargin > 3)
            if(isnumeric(varargin{1}) && varargin{1} >= 1)
                covThr = varargin{1};    
            else
                error('fourth parameter for COV method is threshold (numeric, greater or equal to 1)')
            end
        end          
        if(nargin>4)
            if(isnumeric(varargin{2}) && varargin{2}>0 && varargin{2} <1)
                winLength = varargin{2};    
                aggregPerc = winLength; % default value for aggregPerc: windowLength
            else
                error('fifth parameter for COV method is win length (between 0-1 s)')
            end
        end
        if(nargin > 5)
            if(isnumeric(varargin{3}) && varargin{3} <= 1 && varargin{3} > 0)
                covThr = varargin{3};    
            else
                error('sixth parameter for COV method is aggregation threshold (numeric, greater than 0, lower or equal to 1, multiple of winLength)')
            end
        end               
    otherwise
        error('Unknown method: %s',method)
end

% ---- COMPUTE FEATURES ----
Nfeat = length(featNames); 
if(Nfeat>0) % all methods exc. COV - does not use features
    featVals = nan(Nch*Ns,Nfeat); % channel, second, artif. type
    for si=1:Ns % iterate over seconds
        inds = (si-1)*fs+1 : min(si*fs, N); % pick appropriate channels
        fv = sigInspectComputeFeatures(signal(:,inds),featNames(featComp),fs); % feature values for given second of all channels
        featVals((si-1)*Nch+(1:Nch),featComp) = fv; % store as Nch rows of the feature table
    end
end

% ---- CLASSIFY ----
switch(method)
    case 'psd'
        % compare to preset threshold
        annot = featVals>psdThr;
        % change dims to be Nch*Ns
        annot = reshape(annot,Nch,Ns);
    case 'tree'
        % classify using decision tree
        annot = eval(classif.tree,featVals); 
        annot=strcmp(annot,'1');
        % change dims to be Nch*Ns
        annot = reshape(annot,Nch,Ns);
    case 'cov'
        annot = false(Nch,Ns);
        for chi=1:Nch
            annot(chi,:) = sigInspectClassifyCov(signal(chi,:),fs,'cov', covThr, winLength, aggregPerc,false);
        end
end

