%% Jarsky CA1 PC model generator for TMS simulation
% Based on code by Laura Mediavilla
% Adapted by Nicholas Hananeia, 2019-2020
%%
clear all; clc;
% initialize model folder hierarchy in current folder:
pwd = '../Model/';
t2n_initModelfolders(pwd);
tstop                    = 1100;%40000;
dt                       = 0.05;

% Define standard parameters
neuron.params            = [];
neuron.params.celsius    = 35;
neuron.params.v_init     = -70;
neuron.params.prerun     = 200;
neuron.params.tstop      = tstop;
neuron.params.dt         = dt;
neuron.params.nseg       = 'dlambda';
neuron.params.dlambda    = 0.025;
neuron.params.freq       = 500;

trees = load_tree('./morphos/tree.mtr'); %Specify input morphology here!

axon_type = menu('Choose desired axon:','Do not alter','No axon','Stick axon','Myelinated axon');

%%
for cell_num = 1:length(trees)

%% Load morphology
tname                    = 'Jarsky_model';
treeFilename = './morphos/place_tree.mtr'; %Input file here!
treepath = '';
neuron.params.exchfolder = strcat('../Model/Cell_',num2str(cell_num));
%to de-group the morphologies (if necessary), and have the different tree
%strucutres in the cell array 'tree':


%Load morphologies. Functions to strip the axon or add artificial soma
%provided but not active.
if(length(trees) == 1)
    tree{1,1} = trees;
else
    tree{1,1} = trees{1,1};
end
tree{1,1} = tran_tree(tree{1,1}, [tree{1,1}.X(1), tree{1,1}.Y(1), tree{1,1}.Z(1)].*(-1));

if(axon_type == 2 || axon_type == 3)
    tree{1,1} = strip_axon(tree{1,1});
end

%% Divide the tree morphology (if it hasn't been divided before)
for t                    = 1 : numel (tree)
    % option j jarsky?, axon include axon
    %tree{t}.R            = tree{t}.R * 0 + 2;
    %tree{t}.R (1)        = 1;
    tree{t}.rnames       = {'soma', 'axon', 'dendrite' 'dendrite'};
    if(axon_type == 3)
        tree{1,1} = add_axon(tree{1,1});
    end
    if(axon_type == 4)
        tree{t} = myelinate_axon(tree{t});
    end
    tree{t}              = CA1pyramidalcell_sort_Jmodel_len(tree{t},'-j -axon');
end 


figure(cell_num);
xplore_tree(tree{t}, '-2');


%% Convert the tree into NEURON
for t                    = 1 : numel (tree)
    if ~all (cellfun (@(x) isfield (x, 'NID'), tree)) || ...
            ~all (cellfun (@(x) exist (fullfile ( ...
            pwd, 'morphos', 'hocs', [x.NID, '.hoc']), 'file'), ...
            tree))
        answer = 'OK';
        if strcmp        (answer, 'OK')
            tree{t}      = sort_tree      (tree{t}, '-LO');
            tname = strcat('Jarsky_',num2str(cell_num));
            % Tanslation of morphologies into hoc file:
            tree         = t2n_writeTrees (tree,tname, fullfile (treepath, treeFilename));
        end
    end
end

%% Add passive parameters
cm                       = 0.75;              % Membrane capacitance (�F/cm�)
Ra                       = 200;               % Cytoplasmic resistivity (ohm*cm)
Rm                       = 40000;             % Membrane resistance (ohm/cm�) (uniform)
gpas                     = 1;
e_pas                    = -66;
cm_axonmyel              = 0.01;
Rm_axonnode              = 50;
for t                    = 1 : numel (tree)
    % do not scale spines:
    neuron.mech{t}.all.pas      = struct ( ...
        'cm',        cm,  ...
        'Ra',        Ra,  ...
        'g',         gpas / Rm,  ...
        'e',         e_pas);
end

%% Add active mechanisms
% To get the regions that should be ranged:
% taken the regions from tree 1 because all of them have the same region
% definition:
treeregions              = tree{1}.rnames;
noregions                = {'soma', 'basal', 'hill', 'iseg', 'myelin', 'node'};
x                        = false (size (treeregions));
for r                    = 1 : numel (noregions)
    % <-- Flag the ones that noregions{r} matches:
    x                    = x | ~cellfun (@isempty, strfind (treeregions, noregions{r}));
end
treeregions (x)          = [];    % <-- Delete all the flagged lines at once
% ********** Na conductance (gNabar)
nainfo.gbar              = 0.040;                % in S/cm2
nainfo.gnode             = 30.0;                % in S/cm2
nainfo.region            = treeregions;
% ********** Delayed rectifier K+ conducatnce (gKdr)
gkdr                     = 0.040;                       % in S/cm2 (uniform)
% ********** A-type K+ channel proximal (gAKp) and distal (gAKd)
kainfo.gka               = 0.048;                 % in S/cm2
kainfo.gka_ax            = kainfo.gka * 0.2;     % in S/cm2
kainfo.ek                = -77;
kainfo.region            = treeregions;
for t                    = 1 : numel (tree)
    % Distribution of the channels that depend on path distance
    vec_gNa{t}                    = range_conductanceNa (nainfo, tree{t}, ...
        '-wE'); % some option determining excitability
    vec_gKa{t}                    = range_conductanceKa (kainfo, tree{t});
    
    neuron.mech{t}.range.nax      = struct ( ...
        'gbar',                vec_gNa{t});
    neuron.mech{t}.all.nax        = struct ( ...
        'gbar',                nainfo.gbar, ...
        'ena',                 55);
    
    neuron.mech{t}.all.kdr        = struct ( ...
        'gkdrbar', gkdr, ...
        'ek',                  -77);
    
    neuron.mech{t}.kap            = struct ( ...
        'gkabar',              vec_gKa{t}.proximal);
    neuron.mech{t}.all.kap        = struct ( ...
        'gkabar',              kainfo.gka, ...
        'ek',                  -77);
    neuron.mech{t}.all.kad = struct();
    
    neuron.mech{t}.range.kad      = struct ( ...
        'gkabar',              vec_gKa{t}.distal);
    neuron.mech{t}.proxAp.kad     = struct ( ...
        'gkabar',              kainfo.gka, ...
        'ek',                  -77);
    neuron.mech{t}.middleAp.kad   = struct ( ...
        'gkabar',              kainfo.gka, ...
        'ek',                  -77);
    neuron.mech{t}.distalAp.kad   = struct ( ...
        'gkabar',              kainfo.gka, ...
        'ek',                  -77);
    neuron.mech{t}.tuft.kad       = struct ( ...
        'gkabar',              kainfo.gka, ...
        'ek',                  -77);
    %Myelin segments have lowered membrane capacitance
    neuron.mech{t}.myelin.pas = struct(...
        'cm', 0.01, ...
        'g_pas', 1/1.125e6);
    %AIS, nodes, and unmyelinated axon have elevated sodium conductance
    neuron.mech{t}.iseg.nax = struct(...
        'gbar', 15, ...
        'ena', 50);
    neuron.mech{t}.node.nax = struct(...
        'gbar', 15, ...
        'ena', 50);
    neuron.mech{t}.axon.nax = struct(...
        'gbar', 15, ...
        'ena', 50);
   neuron.mech{t}.all.xtra = struct();
   neuron.mech{t}.all.extracellular = struct();


end
neuron_orig = neuron;

%% Set up cells and run basic simulation with no inputs
cells                    = tree;             % tree morphologies without the source stimulation cells
N                        = 1;                           % Number of Simulations
regions                  = {'basal','proxAp','middleAp','distalAp','tuft'};   % Regions where synapses should be placed
for t                    = 1 : numel (tree)
    % array with as many zeros as nodes in the tree:
    dend{t}              = zeros (size (tree{t}.X), 'double');
    for sim              = 1 : numel (regions)
        % Get ones in the regions you want to activate:
        dend{t}          = dend{t} + double (...
            tree{t}.R (:) == find (strcmp (regions{sim}, tree{t}.rnames)));
    end
    % Get ones in the regions you do not want to activate:
    rest{t}              = double (abs (dend{t}-ones (size (tree{t}.X), 'double')));
    % Calculate the length of each group of regions in order to be able to
    % activate per density:
    dendlength (t)       = sum (len_tree (tree{t}).*dend{t});                    
    restlength (t)       = sum (len_tree (tree{t}).*rest{t});
end


for t = 1:numel (cells)
   neuronn{t} = neuron;
    iseg_nodes{t} = find(cells{t}.R == find(strcmp(cells{t}.rnames, 'iseg')));
    recnodes = 1;
    neuronn{t}.record{t}.cell = struct('node',recnodes,'record',{'v'});
    nneuron{t}.custom{t}       = [];
end

%This will generate a segmentation fault error; ignore it and save outputs
try
out              = t2n (neuronn,tree, '-d-w-q');
time             = out{1}.t;
catch
end
disp(strcat('Cell number  ', num2str(cell_num), ' complete.'))
%V                = zeros (length (time) ,length (out));

% for counter      = 1 : length (out)
%      V (:, counter) = out{counter}.record{counter}.cell.v{1};
%  end

end

%% Copy across necessary files to model folder
copyfile('./morphos/', '../Model/morphos/', 'f');
copyfile('./lib_custom/', '../Model/lib_custom/', 'f');
copyfile('./lib_genroutines/', '../Model/lib_genroutines/', 'f');
copyfile('./lib_mech/', '../Model/lib_mech/', 'f');

for i = 1:numel(trees)
    copyfile('./TMS package/', strcat('../Model/Cell_', num2str(i), '/sim1/'), 'f');
end
















